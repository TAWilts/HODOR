function [status, message, httpCode, retryAfter] = downloadFile(url, destination, expectedBytes, opts)
%DOWNLOADFILE Download to .part, optionally resume with HTTP Range.
% Never promote a partial file without checking its expected byte count (if known).
arguments
    url (1,1) string
    destination (1,1) string
    expectedBytes (1,1) double
    opts.Timeout (1,1) double = 180
    opts.Retries (1,1) double = 4
    opts.RetryDelay (1,1) double = 5
    opts.Force (1,1) logical = false
    opts.ResetPartial (1,1) logical = true
end
folder = fileparts(destination);
if ~isfolder(folder), mkdir(folder); end
part = destination + ".part";
httpCode = NaN;
retryAfter = 0;
if opts.Force && opts.ResetPartial && isfile(part), delete(part); end
if isfile(destination) && ~opts.Force
    info = dir(destination);
    if info.bytes>0 && (~isfinite(expectedBytes) || info.bytes==expectedBytes)
        status = "SKIPPED";
        message = "Existing file matches published byte size";
        if ~isfinite(expectedBytes)
            message = "Existing nonempty file; published byte size unavailable";
        end
        return
    end
    % Keep the existing file intact; a successful new download will replace it.
end
status = "FAILED";
message = "Download not attempted";
for attempt = 1:(opts.Retries+1)
    responseCleanup = []; %#ok<NASGU> % Remove only the previous staged response.
    fid = -1;
    httpCode = NaN;
    retryAfter = 0;
    offset = 0;
    if isfile(part)
        d = dir(part);
        offset = d.bytes;
    end
    try
        if isfinite(expectedBytes) && offset==expectedBytes && offset>0
            movefile(part, destination, 'f');
            status = "DOWNLOADED";
            message = "Completed pre-existing partial file";
            return
        end
        if isfinite(expectedBytes) && offset>expectedBytes
            delete(part);
            offset = 0;
        end
        % Save the unencoded payload so byte counts refer to the saved file.
        fields = matlab.net.http.HeaderField('Accept-Encoding','identity');
        transferFile = part;
        if offset>0
            fields(end+1) = matlab.net.http.HeaderField('Range', sprintf('bytes=%d-',offset));
            % Do not append an error page or an unverified range to good bytes.
            transferFile = string(tempname(folder)) + ".response";
            responseCleanup = onCleanup(@()removeResponse(transferFile));
        end
        fid = fopen(transferFile, 'wb');
        if fid<0
            error('hodor:FileAccess', 'Cannot write %s',transferFile);
        end
        req = matlab.net.http.RequestMessage('GET',fields);
        options = matlab.net.http.HTTPOptions('ConnectTimeout',opts.Timeout, ...
            'ResponseTimeout',opts.Timeout,'DataTimeout',opts.Timeout);
        consumer = matlab.net.http.io.FileConsumer(fid);
        response = send(req, matlab.net.URI(char(url)), options, consumer);
        fclose(fid);
        fid = -1;
        code = double(response.StatusCode);
        httpCode = code;
        if code==429 || code==503 || code==202
            retryAfter = readRetryAfter(response);
        end
        accepted = false;
        targetBytes = expectedBytes;
        if code==200
            received = dir(transferFile);
            checkContentLength(response,received.bytes);
            if offset>0
                % An ignored Range may return a complete file. Replace the old
                % partial only after that separate response has been checked.
                if received.bytes==0 || ...
                        isfinite(expectedBytes) && received.bytes~=expectedBytes
                    error('hodor:IncompleteDownload', ...
                        'Server ignored HTTP Range; incomplete full response (%d bytes).',received.bytes);
                end
                movefile(transferFile,part,'f');
            end
            accepted = true;
        elseif code==206
            if offset==0
                delete(part);
                error('hodor:InvalidRange','Unexpected partial HTTP response.');
            end
            received = dir(transferFile);
            targetBytes = checkRange(response,offset,received.bytes,expectedBytes);
            appendResponse(transferFile,part);
            accepted = true;
        else
            % A tape-retrieval/error response must not discard an existing prefix.
            if offset==0 && isfile(part), delete(part); end
            if code==503 || code==202
                message = sprintf('HTTP %d (resource temporarily unavailable; possibly archive retrieval)',code);
            else
                message = sprintf('HTTP %d',code);
            end
        end
        if accepted
            d = dir(part);
            if d.bytes==0
                message = "Empty HTTP response";
            elseif isfinite(targetBytes) && d.bytes~=targetBytes
                message = sprintf('Incomplete download: %d / %.0f bytes',d.bytes,targetBytes);
                if d.bytes>targetBytes && offset==0, delete(part); end
            else
                movefile(part, destination, 'f');
                status = "DOWNLOADED";
                message = sprintf('Downloaded %d bytes',d.bytes);
                return
            end
        end
    catch ME
        if fid>=0, fclose(fid); end
        message = string(ME.message);
        % Retain good partial bytes, allowing the next attempt to resume.
    end
    if attempt<=opts.Retries
        fprintf('  Retry %d/%d: %s\n',attempt,opts.Retries,message);
        pause(opts.RetryDelay);
    end
end
end

function delay = readRetryAfter(response)
% Accept either delta seconds or a standard HTTP date (RFC 9110).
delay = 0;
field = response.getFields('Retry-After');
if ~isscalar(field), return; end
try
    value = strtrim(string(field.Value));
    if ~isscalar(value) || ismissing(value), return; end
    if ~isempty(regexp(char(value),'^[0-9]+$','once'))
        d = str2double(value);
    else
        date = datetime(value,'InputFormat',"eee, dd MMM yyyy HH:mm:ss 'GMT'", ...
            'Locale','en_US','TimeZone','UTC');
        d = seconds(date-datetime('now','TimeZone','UTC'));
    end
    if isfinite(d), delay = max(0,d); end
catch
    % An unparseable server header falls back to the configured interval.
end
end

function checkContentLength(response,receivedBytes)
% MATLAB may warn, rather than throw, when a response body ends early.
field = response.getFields('Content-Length');
if isempty(field), return; end
if ~isscalar(field)
    error('hodor:InvalidResponse','Ambiguous HTTP Content-Length.');
end
declaredBytes = str2double(string(field.Value));
if ~isfinite(declaredBytes) || declaredBytes<0 || declaredBytes~=floor(declaredBytes)
    error('hodor:InvalidResponse','Invalid HTTP Content-Length.');
end
if receivedBytes~=declaredBytes
    error('hodor:IncompleteDownload', ...
        'Incomplete HTTP response: %d / %.0f Content-Length bytes.',receivedBytes,declaredBytes);
end
end

function total = checkRange(response,offset,receivedBytes,expectedBytes)
% Check the complete range before its separately staged bytes are appended.
field = response.getFields('Content-Range');
parts = {};
if isscalar(field)
    parts = regexpi(char(strtrim(string(field.Value))), ...
        '^bytes (\d+)-(\d+)/(\d+)$','tokens','once');
end
if isempty(parts)
    error('hodor:InvalidRange','Missing or invalid HTTP Content-Range.');
end
values = str2double(parts);
first = values(1);
last = values(2);
total = values(3);
if any(~isfinite(values)) || first~=offset || last<first || ...
        last>=total || receivedBytes~=last-first+1 || ...
        isfinite(expectedBytes) && total~=expectedBytes
    error('hodor:InvalidRange','HTTP Content-Range does not match requested offset, length or total.');
end
end

function appendResponse(source,destination)
input = fopen(source,'rb');
if input<0, error('hodor:FileAccess','Cannot read %s',source); end
inputCleanup = onCleanup(@()fclose(input));
output = fopen(destination,'ab');
if output<0, error('hodor:FileAccess','Cannot append to %s',destination); end
outputCleanup = onCleanup(@()fclose(output));
sourceInfo = dir(source);
remaining = sourceInfo.bytes;
while remaining>0
    requested = min(1024*1024,remaining);
    bytes = fread(input,requested,'*uint8');
    if numel(bytes)~=requested
        error('hodor:FileAccess','Unable to read the full staged HTTP response.');
    end
    if fwrite(output,bytes,'uint8')~=numel(bytes)
        error('hodor:FileAccess','Unable to append the full HTTP response.');
    end
    remaining = remaining-numel(bytes);
end
end

function removeResponse(filename)
if isfile(filename), delete(filename); end
end
