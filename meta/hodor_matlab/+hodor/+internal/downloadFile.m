function [status, message] = downloadFile(url, destination, expectedBytes, opts)
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
end
folder = fileparts(destination);
if ~isfolder(folder), mkdir(folder); end
part = destination + ".part";
if opts.Force && isfile(part), delete(part); end
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
    offset = 0;
    if isfile(part)
        d = dir(part);
        offset = d.bytes;
    end
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
    permission = 'wb';
    fields = matlab.net.http.HeaderField.empty;
    if offset>0
        permission = 'ab';
        fields = matlab.net.http.HeaderField('Range', sprintf('bytes=%d-',offset));
    end
    fid = fopen(part, permission);
    if fid<0
        error('hodor:FileAccess', 'Cannot write %s',part);
    end
    try
        req = matlab.net.http.RequestMessage('GET',fields);
        options = matlab.net.http.HTTPOptions('ResponseTimeout',opts.Timeout);
        consumer = matlab.net.http.io.FileConsumer(fid);
        response = send(req, matlab.net.URI(char(url)), options, consumer);
        fclose(fid);
        code = double(response.StatusCode);
        if code==200 && offset>0
            % Server ignored Range and sent a whole file: do not append it.
            delete(part);
            message = "Server ignored HTTP Range; restarting from zero";
        elseif code==206 && offset==0
            delete(part);
            message = "Unexpected partial HTTP response";
        elseif code==200 || code==206
            d = dir(part);
            if d.bytes==0
                message = "Empty HTTP response";
            elseif isfinite(expectedBytes) && d.bytes~=expectedBytes
                message = sprintf('Incomplete download: %d / %.0f bytes',d.bytes,expectedBytes);
                if d.bytes>expectedBytes, delete(part); end
            else
                movefile(part, destination, 'f');
                status = "DOWNLOADED";
                message = sprintf('Downloaded %d bytes',d.bytes);
                return
            end
        else
            % PANGAEA may return 202 while files are retrieved from tape.
            if isfile(part), delete(part); end
            message = sprintf('HTTP %d (PANGAEA may still be retrieving from tape)', code);
        end
    catch ME
        fclose(fid);
        message = string(ME.message);
        % Retain partial bytes, allowing the next attempt to resume.
    end
    if attempt<=opts.Retries
        fprintf('  Retry %d/%d: %s\n',attempt,opts.Retries,message);
        pause(opts.RetryDelay);
    end
end
end
