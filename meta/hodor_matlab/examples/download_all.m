function report = download_all(datasetFolder,opts)
%DOWNLOAD_ALL Download all HODOR media in bounded sequence batches.
%   report = download_all("D:\HODOR",'ConfirmFullDownload',true)
%   report = download_all("D:\HODOR",'IDs',[0 1],'Sensors',"sonar")
% Existing files are skipped by the ordinary HODOR downloader. No deletion.
arguments
    datasetFolder (1,1) string
    opts.IDs double = []
    opts.Sensors (1,:) string = ["sonar","cam1","cam2"]
    opts.BatchSize (1,1) double {mustBePositive,mustBeInteger,mustBeFinite} = 10
    opts.ConfirmFullDownload (1,1) logical = false
    opts.RetryDelay (1,1) double {mustBeNonnegative,mustBeFinite} = 1
    opts.SubRetries (1,1) double {mustBeNonnegative,mustBeInteger,mustBeFinite} = 10
    opts.Retries (1,1) double {mustBeNonnegative,mustBeInteger,mustBeFinite} = 5
    opts.Timeout (1,1) double {mustBePositive,mustBeFinite} = 180
    opts.RecordSHA256 (1,1) logical = false
end
if isempty(opts.IDs) && ~opts.ConfirmFullDownload
    error('hodor:ConfirmFullDownload', ...
        'Full HODOR download is large. Set ConfirmFullDownload=true, or supply a small IDs vector.');
end
addpath(fileparts(fileparts(mfilename('fullpath'))));
ds = hodor.HODORDataset(datasetFolder,'Timeout',opts.Timeout, ...
    'RetryDelay',opts.RetryDelay,'SubRetries',opts.SubRetries,'Retries',opts.Retries);
ids = opts.IDs;
if isempty(ids), ids = ds.sequences.sequenceNo; end
ids = unique(ids(:),'stable');
% Validate the complete selection before any media transfer.
files = ds.listFiles(ids,'Sensors',opts.Sensors);
fprintf('Selected %d sequences, %d files. Verify available disk space before continuing.\n', ...
    numel(ids),height(files));
nBatches = ceil(numel(ids)/opts.BatchSize);
parts = cell(nBatches,1);
for b = 1:nBatches
    ix = (b-1)*opts.BatchSize+1:min(b*opts.BatchSize,numel(ids));
    fprintf('Batch %d/%d: %d sequences\n',b,nBatches,numel(ix));
    parts{b} = ds.downloadSequence(ids(ix),'Sensors',opts.Sensors, ...
        'Force',false,'Validate',false,'RecordSHA256',opts.RecordSHA256);
    fprintf('Batch %d/%d finished: %d downloaded, %d skipped, %d failed.\n', ...
        b,nBatches,nnz(parts{b}.Status=="DOWNLOADED"), ...
        nnz(parts{b}.Status=="SKIPPED"),nnz(parts{b}.Status=="FAILED"));
end
report = vertcat(parts{:});
% The normal download manifest is updated after each batch. This is an
% additional summary of this invocation, not a checkpoint for skipping files.
writetable(report,fullfile(datasetFolder,'reports','download_all.csv'));
fprintf('Total: %d downloaded, %d skipped, %d failed.\n', ...
    nnz(report.Status=="DOWNLOADED"),nnz(report.Status=="SKIPPED"),nnz(report.Status=="FAILED"));
end
