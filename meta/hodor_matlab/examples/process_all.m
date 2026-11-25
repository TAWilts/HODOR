function report = process_all(workFolder,processor,opts)
%PROCESS_ALL Download one file, process, save result, delete, then repeat.
%   report = process_all("D:\HODOR_processing",[],'IDs',0,'Sensors',"sonar")
%   report = process_all("D:\HODOR_processing",@myProcessor,'ConfirmFullDownload',true)
% processor(file) receives a one-row manifest table with Path in private
% scratch storage and returns a MATLAB value. [] uses a frame/TXT count example.
% Use a different workFolder when changing processing algorithms or settings.
arguments
    workFolder (1,1) string
    processor = []
    opts.IDs double = []
    opts.Sensors (1,:) string = ["sonar","cam1","cam2"]
    opts.ConfirmFullDownload (1,1) logical = false
    opts.RetryDelay (1,1) double {mustBeNonnegative,mustBeFinite} = 1
    opts.SubRetries (1,1) double {mustBeNonnegative,mustBeInteger,mustBeFinite} = 10
    opts.Retries (1,1) double {mustBeNonnegative,mustBeInteger,mustBeFinite} = 5
    opts.Timeout (1,1) double {mustBePositive,mustBeFinite} = 180
    opts.ShowProgress (1,1) logical = true
end
if isempty(opts.IDs) && ~opts.ConfirmFullDownload
    error('hodor:ConfirmFullDownload', ...
        'Full HODOR processing transfers the entire selection. Set ConfirmFullDownload=true or supply IDs.');
end
if isempty(processor), processor = @exampleProcessor; end
if ~isa(processor,'function_handle') || ~isscalar(processor)
    error('hodor:InvalidProcessor','Processor must be a scalar function handle.');
end
addpath(fileparts(fileparts(mfilename('fullpath'))));
% Never use an existing dataset's media folder as scratch.
ds = hodor.HODORDataset(fullfile(workFolder,'metadata'),'Timeout',opts.Timeout, ...
    'RetryDelay',opts.RetryDelay,'SubRetries',opts.SubRetries,'Retries',opts.Retries);
ids = opts.IDs;
if isempty(ids), ids = ds.sequences.sequenceNo; end
files = ds.listFiles(ids,'Sensors',opts.Sensors);
resultsFolder = fullfile(workFolder,'results');
scratchParent = fullfile(workFolder,'scratch');
if ~isfolder(resultsFolder), mkdir(resultsFolder); end
if ~isfolder(scratchParent), mkdir(scratchParent); end
% Unique per invocation; stale failed scratch is never removed automatically.
scratch = string(tempname(scratchParent));
mkdir(scratch);
fprintf('Processing %d individual files. Scratch: %s\n',height(files),scratch);
progress = hodor.internal.DownloadProgress(height(files),opts.ShowProgress);
report = files(:,{'SeqID','Sensor','Kind','RelativePath'});
report.Status = repmat("NOT_RUN",height(files),1);
report.Message = strings(height(files),1);
report.ResultPath = strings(height(files),1);
report.ScratchPath = strings(height(files),1);
for k = 1:height(files)
    progress.update(k-1,"Processing "+files.RelativePath(k));
    [s,m,out,raw] = hodor.internal.processOneFile(files(k,:),scratch,resultsFolder, ...
        processor,@downloadOne);
    report.Status(k) = s;
    report.Message(k) = m;
    report.ResultPath(k) = out;
    report.ScratchPath(k) = raw;
    if ~ismember(s,["PROCESSED","SKIPPED"])
        progress.clearLine();
        warning('hodor:ProcessingStopped','Stopped at %s: %s. Scratch: %s', ...
            files.RelativePath(k),m,scratch);
        break
    end
    progress.update(k,s+" "+files.RelativePath(k));
end
entries = dir(scratch);
if all(ismember(string({entries.name}),[".",".."]))
    rmdir(scratch); % Nonrecursive: never remove unrelated files.
end
writetable(report,fullfile(workFolder,'process_all.csv'));
fprintf('Processed %d, skipped %d, not completed %d. Results: %s\n', ...
    nnz(report.Status=="PROCESSED"),nnz(report.Status=="SKIPPED"), ...
    nnz(~ismember(report.Status,["PROCESSED","SKIPPED"])),resultsFolder);

    function [status,message] = downloadOne(file)
        [status,message] = hodor.internal.downloadQueue(1, ...
            @(~,first) hodor.internal.downloadFile(file.URL,file.Path,file.ExpectedBytes, ...
                'Timeout',opts.Timeout,'Retries',0,'ResetPartial',first), ...
            'RetryDelay',opts.RetryDelay,'SubRetries',opts.SubRetries,'Retries',opts.Retries);
    end
end

function result = exampleProcessor(file)
% Replace this with your own analysis. Only one frame is held at a time.
if file.Kind=="Video"
    reader = VideoReader(file.Path);
    n = 0;
    sumBrightness = 0;
    while hasFrame(reader)
        frame = readFrame(reader);
        n = n+1;
        sumBrightness = sumBrightness+mean(double(frame(:)));
    end
    assert(n>0,'No video frames decoded.');
    result = struct('FrameCount',n,'MeanBrightness',sumBrightness/n, ...
        'FrameRate',reader.FrameRate,'Duration',reader.Duration);
else
    lines = strtrim(readlines(file.Path));
    values = str2double(lines(strlength(lines)>0));
    assert(~isempty(values) && all(isfinite(values)),'Invalid timestamp data.');
    result = struct('TimestampCount',numel(values),'FirstTimestamp',values(1), ...
        'LastTimestamp',values(end),'Monotonic',all(diff(values)>=0));
end
end
