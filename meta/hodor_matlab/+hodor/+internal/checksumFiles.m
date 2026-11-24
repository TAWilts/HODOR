function report = checksumFiles(root,files,mode,origin)
%CHECKSUMFILES Record immutable local baselines or verify existing ones.
% No implicit overwrite, network access, or media modification.
arguments
    root (1,1) string
    files table
    mode (1,1) string {mustBeMember(mode,["record","verify"])}
    origin (1,1) string {mustBeMember(origin,["local","download"])} = "local"
end
filename = fullfile(root,'meta','checksums_sha256.tsv');
baseline = readBaseline(filename);
report = files(:,{'SeqID','Sensor','Kind','RelativePath','Path'});
n = height(report);
report.ExpectedSHA256 = strings(n,1);
report.ActualSHA256 = strings(n,1);
report.ReferenceBytes = NaN(n,1);
report.Bytes = NaN(n,1);
report.Origin = strings(n,1);
report.Status = strings(n,1);
report.Message = strings(n,1);
added = false;
[known,indices] = ismember(report.RelativePath,baseline.RelativePath);
for k = 1:n
    key = report.RelativePath(k);
    if ~validKey(key), error('hodor:ChecksumPath','Noncanonical checksum path: %s',key); end
    if known(k)
        row = baseline(indices(k),:);
        report.ExpectedSHA256(k) = row.SHA256;
        report.ReferenceBytes(k) = row.Bytes;
        report.Origin(k) = row.Origin;
    end
    if ~isfile(report.Path(k))
        report.Status(k) = "MISSING";
        report.Message(k) = "Expected file is missing";
        continue
    end
    stat = dir(report.Path(k));
    report.Bytes(k) = stat.bytes;
    if stat.bytes==0
        report.Status(k) = "EMPTY";
        report.Message(k) = "Empty file is not a valid HODOR baseline";
        continue
    end
    if mode=="verify" && ~known(k)
        report.Status(k) = "NO_BASELINE";
        report.Message(k) = "No local SHA-256 baseline";
        continue
    end
    try
        [digest,bytes] = hodor.internal.sha256File(report.Path(k));
        if bytes==0, error('hodor:ChecksumEmpty','File became empty.'); end
        report.ActualSHA256(k) = digest;
        report.Bytes(k) = bytes;
        if known(k)
            if digest==row.SHA256 && bytes==row.Bytes
                report.Status(k) = "MATCH";
                report.Message(k) = "Matches previously recorded local baseline";
            else
                report.Status(k) = "MISMATCH";
                report.Message(k) = "Local baseline differs; original reference retained";
            end
        else
            stamp = string(datetime('now','TimeZone','UTC', ...
                'Format',"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"));
            baseline(end+1,:) = {key,digest,bytes,stamp,origin}; %#ok<AGROW>
            added = true;
            report.ExpectedSHA256(k) = digest;
            report.ReferenceBytes(k) = bytes;
            report.Origin(k) = origin;
            report.Status(k) = "RECORDED";
            report.Message(k) = "Local baseline created; not a publisher checksum";
        end
    catch ME
        report.Status(k) = "ERROR";
        report.Message(k) = string(ME.identifier)+": "+string(ME.message);
    end
end
if added
    folder = fileparts(filename);
    if ~isfolder(folder), mkdir(folder); end
    tmp = string(tempname(folder))+".tsv";
    cleanup = onCleanup(@()removeTemp(tmp)); %#ok<NASGU>
    baseline = sortrows(baseline,'RelativePath');
    writetable(baseline,tmp,'FileType','text','Delimiter','tab');
    % Validate the staged manifest before replacing the previous reference.
    readBaseline(tmp);
    [ok,msg] = movefile(tmp,filename,'f');
    if ~ok, error('hodor:ChecksumManifestWrite','%s',msg); end
end
end

function baseline = readBaseline(filename)
names = ["RelativePath","SHA256","Bytes","RecordedUTC","Origin"];
baseline = table('Size',[0,5], ...
    'VariableTypes',{'string','string','double','string','string'}, ...
    'VariableNames',cellstr(names));
if ~isfile(filename), return; end
[header,data] = hodor.internal.readTab(filename,"RelativePath");
if ~isequal(header,names)
    error('hodor:ChecksumManifest','Unexpected SHA-256 manifest schema.');
end
if isempty(data), return; end
bytes = str2double(data(:,3));
for k=1:size(data,1)
    if ~validKey(data(k,1)) || ...
            isempty(regexp(char(data(k,2)),'^[0-9a-f]{64}$','once')) || ...
            ~isfinite(bytes(k)) || bytes(k)<=0 || bytes(k)~=floor(bytes(k)) || ...
            bytes(k)>flintmax || ...
            isempty(regexp(char(data(k,4)),'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$','once')) || ...
            ~ismember(data(k,5),["local","download"])
        error('hodor:ChecksumManifest','Invalid SHA-256 manifest row %d.',k);
    end
end
if numel(unique(data(:,1)))~=size(data,1)
    error('hodor:ChecksumManifest','Duplicate SHA-256 manifest paths.');
end
baseline = table(data(:,1),data(:,2),bytes,data(:,4),data(:,5), ...
    'VariableNames',cellstr(names));
end

function yes = validKey(key)
yes = ~ismissing(key) && ~isempty(regexp(char(key), ...
    '^(sonar/sonar|camera/cam[12])_[0-9]{4}\.(mp4|txt)$','once'));
end

function removeTemp(filename)
if isfile(filename), delete(filename); end
end
