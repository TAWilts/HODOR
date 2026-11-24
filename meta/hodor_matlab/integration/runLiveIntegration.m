function result = runLiveIntegration(opts)
%RUNLIVEINTEGRATION Opt-in, bounded preflight for real HODOR stereo downloads.
%   result = runLiveIntegration()
%       HEAD only, no media GET requests.
%   result = runLiveIntegration('Download',true)
%       Test the first reachable stereo sequence within the preflight budget.
%   result = runLiveIntegration('Download',true,'IncludeSonar',true,'Deep',true)
%       Test a complete sequence, including all timestamp sidecars.
%
% Results and media are retained in a NEW temporary dataset, never in a
% production dataset. This is intentionally outside the offline CI suite.
% MaxBytes limits the advertised HEAD total, not a hard network byte cap.
arguments
    opts.Download (1,1) logical = false
    opts.IncludeSonar (1,1) logical = false
    opts.Deep (1,1) logical = false
    opts.CandidateIDs (1,:) double {mustBeInteger,mustBeNonnegative,mustBeFinite} = []
    opts.MaxCandidates (1,1) double {mustBeInteger,mustBePositive,mustBeFinite} = 5
    opts.MaxBytes (1,1) double {mustBeInteger,mustBePositive,mustBeFinite} = 100*1024^2
    opts.Timeout (1,1) double {mustBePositive,mustBeFinite} = 60
    opts.ParentFolder (1,1) string = string(tempdir)
end
if opts.MaxCandidates>10
    error('hodor:IntegrationBudget','At most 10 candidate sequences per run.');
end
if any(opts.CandidateIDs>5849)
    error('hodor:UnknownSequence','Candidate IDs must be in 0:5849.');
end
if ~isfolder(opts.ParentFolder)
    error('hodor:IntegrationFolder','ParentFolder must already exist.');
end
suiteFolder = fileparts(fileparts(mfilename('fullpath')));
oldPath = path;
restorePath = onCleanup(@()path(oldPath)); %#ok<NASGU>
addpath(suiteFolder);
root = string(tempname(opts.ParentFolder));
mkdir(root);
reports = fullfile(root,'reports');
mkdir(reports);
result = struct('Status',"FAIL",'Reason',"Not completed",'Folder',root, ...
    'SeqID',NaN,'PreflightBytes',NaN,'DownloadedBytes',NaN, ...
    'WarningRows',0,'DeepRun',false);
fprintf('HODOR integration QA folder: %s\n',root);
try
    ds = hodor.HODORDataset(root,'Timeout',opts.Timeout,'Retries',0);
    sequences = ds.sequences;
    sensors = ["cam1","cam2"];
    if opts.IncludeSonar, sensors = ["sonar",sensors]; end
    if isempty(opts.CandidateIDs)
        % Try the previously investigated IDs and then short sequences.
        [~,order] = sort(sequences.sequence_length);
        candidates = unique([0;2900;sequences.sequenceNo(order)],'stable');
    else
        candidates = unique(opts.CandidateIDs(:),'stable');
    end
    candidates = candidates(1:min(numel(candidates),opts.MaxCandidates));
    probes = table();
    selected = table();
    for id = candidates.'
        files = hodor.internal.fileManifest(root,sequences,id,sensors,table());
        probe = files(:,{'SeqID','Sensor','Kind','Path','URL'});
        probe.HTTPStatus = NaN(height(probe),1);
        probe.HeadBytes = NaN(height(probe),1);
        probe.Message = strings(height(probe),1);
        for k = 1:height(probe)
            [probe.HTTPStatus(k),probe.HeadBytes(k),probe.Message(k)] = ...
                probeHead(probe.URL(k),opts.Timeout);
        end
        if isempty(probes), probes = probe; else, probes = [probes;probe]; end %#ok<AGROW>
        writetable(probes,fullfile(reports,'head_probes.csv'));
        if all(probe.HTTPStatus==200 & isfinite(probe.HeadBytes) & probe.HeadBytes>0) ...
                && sum(probe.HeadBytes)<=opts.MaxBytes
            selected = probe;
            result.SeqID = id;
            result.PreflightBytes = sum(probe.HeadBytes);
            break
        end
    end
    if isempty(selected)
        result.Status = "BLOCKED";
        result.Reason = "No candidate with all required HEAD responses HTTP 200 and known sizes within budget.";
    elseif ~opts.Download
        result.Status = "READY";
        result.Reason = "HEAD preflight succeeded; no media downloaded (Download=false).";
    else
        fprintf('Selected sequence %04d; advertised bytes: %.0f\n', ...
            result.SeqID,result.PreflightBytes);
        result = exerciseDataset(ds,selected,sensors,reports,result,opts);
    end
catch ME
    result.Status = "FAIL";
    result.Reason = string(ME.identifier)+": "+string(ME.message);
    writelines(string(getReport(ME,'extended','hyperlinks','off')), ...
        fullfile(reports,'exception.txt'));
end
writelines(string(jsonencode(result,PrettyPrint=true)), ...
    fullfile(reports,'integration_summary.json'));
disp(result)
end

function [code,bytes,message] = probeHead(url,timeout)
code = NaN;
bytes = NaN;
message = "";
try
    headers = matlab.net.http.HeaderField('Accept-Encoding','identity');
    req = matlab.net.http.RequestMessage('HEAD',headers);
    options = matlab.net.http.HTTPOptions('ConnectTimeout',timeout, ...
        'ResponseTimeout',timeout,'DataTimeout',timeout);
    response = send(req,matlab.net.URI(char(url)),options);
    code = double(response.StatusCode);
    if code~=200
        message = "HTTP "+string(code)+"; media not requested";
        return
    end
    type = response.getFields('Content-Type');
    if ~isempty(type) && any(contains(lower(string({type.Value})),'text/html'))
        message = "Unexpected HTML response";
        return
    end
    encoding = response.getFields('Content-Encoding');
    if ~isempty(encoding) && (~isscalar(encoding) || ...
            ~strcmpi(strtrim(string(encoding.Value)),"identity"))
        message = "Nonidentity Content-Encoding; size not trusted";
        return
    end
    field = response.getFields('Content-Length');
    if isscalar(field)
        value = str2double(string(field.Value));
        if isfinite(value) && value>0 && value==floor(value) && value<=flintmax
            bytes = value;
            message = "Transport Content-Length (not an independent checksum)";
            return
        end
    end
    message = "Missing or invalid Content-Length";
catch ME
    message = string(ME.identifier)+": "+string(ME.message);
end
end

function result = exerciseDataset(ds,selected,sensors,reports,result,opts)
id = result.SeqID;
if opts.IncludeSonar
    download = ds.downloadSequence(id,'Force',false,'Validate',true,'RetryDelay',0);
else
    download = ds.downloadVideo(id,'Force',false,'Validate',true);
end
writetable(download,fullfile(reports,'integration_download.csv'));
assert(height(download)==height(selected),'Unexpected number of download rows.');
[found,idx] = ismember(selected.URL,download.URL);
assert(all(found) && numel(unique(idx))==height(selected), ...
    'Download URLs differ from preflight manifest.');
failed = download.Status=="FAILED";
if any(failed)
    % A server-side refusal or transient failure is not a successful test.
    external = false(sum(failed),1);
    failures = download.Message(failed);
    for k = 1:numel(failures)
        external(k) = ~isempty(regexp(char(failures(k)), ...
            '^HTTP (202|429|502|503|504)( |$)','once'));
    end
    if all(external)
        result.Status = "BLOCKED";
        result.Reason = "PANGAEA returned a transient HTTP status during GET.";
    else
        result.Status = "FAIL";
        result.Reason = "Download failed; see integration_download.csv.";
    end
    return
end
assert(all(download.Status=="DOWNLOADED"), ...
    'A fresh QA dataset must report DOWNLOADED for every requested file.');
actual = NaN(height(selected),1);
modified = NaN(height(selected),1);
for k = 1:height(selected)
    assert(isfile(selected.Path(k)),'Downloaded file missing.');
    d = dir(selected.Path(k));
    actual(k) = d.bytes;
    modified(k) = d.datenum;
    assert(~isfile(selected.Path(k)+".part"),'Unexpected remaining partial file.');
end
result.DownloadedBytes = sum(actual);
selected.ActualBytes = actual;
selected.MatchesHEAD = actual==selected.HeadBytes;
writetable(selected,fullfile(reports,'transport_size_check.csv'));
assert(all(selected.MatchesHEAD),'Actual file sizes differ from preflight HEAD.');
assert(result.DownloadedBytes<=opts.MaxBytes,'Downloaded data exceeded the HEAD budget.');

quick = ds.validateSequence(id,'Sensors',sensors,'Level','quick','SaveReport',true);
standard = ds.validateSequence(id,'Sensors',sensors,'Level','standard','SaveReport',true);
assert(height(quick)==height(selected) && height(standard)==height(selected), ...
    'Validation omitted expected files.');
assert(~any(quick.Status=="FAIL" | standard.Status=="FAIL"), ...
    'Quick or standard validation failed.');
video = standard.Kind=="Video";
timestamp = standard.Kind=="Timestamp";
assert(all(standard.Frames(video)==3), 'Standard must decode all three sample frames per video.');
assert(all(standard.TimestampCount(timestamp)>0),'Timestamp sidecar has no entries.');
assert(~any(contains(standard.Message,"No common temporal overlap")), ...
    'Sensors have no common timestamp coverage.');
result.WarningRows = sum(standard.Status=="WARN");
if opts.Deep
    deep = ds.validateSequence(id,'Sensors',sensors,'Level','deep','SaveReport',true);
    result.DeepRun = true;
    assert(height(deep)==height(selected) && ~any(deep.Status=="FAIL"), ...
        'Deep validation failed or omitted files.');
    assert(all(deep.Frames(deep.Kind=="Video")>0),'No decoded video frames.');
end
if opts.IncludeSonar
    repeated = ds.downloadSequence(id,'Force',false,'Validate',false,'RetryDelay',0);
else
    repeated = ds.downloadVideo(id,'Force',false,'Validate',false);
end
writetable(repeated,fullfile(reports,'integration_repeat.csv'));
assert(height(repeated)==height(selected) && all(repeated.Status=="SKIPPED"), ...
    'Repeat download did not skip every file.');
for k = 1:height(selected)
    d = dir(selected.Path(k));
    assert(d.bytes==actual(k) && d.datenum==modified(k), ...
        'Repeat download modified an existing file.');
end
manifest = readtable(fullfile(reports,'download_manifest.csv'),'TextType','string');
assert(height(manifest)==height(selected) && ...
    numel(unique(manifest.Path))==height(selected) && ...
    all(string(manifest.Status)=="SKIPPED") && ...
    all(ismember(selected.Path,string(manifest.Path))), ...
    'Manifest has missing, duplicate, or stale file rows.');
result.Status = "PASS";
result.Reason = "Download, HEAD-size comparison, validation and repeat-skip passed. Review WARN rows; no cryptographic integrity claim.";
end
