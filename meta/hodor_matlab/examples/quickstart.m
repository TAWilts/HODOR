%% HODOR native MATLAB quickstart
% Run addpath('path/to/meta/hodor_matlab') first (or use setup.m).
ds = hodor.HODORDataset(fullfile(pwd,'HODOR'));

% Download activity-count metadata on first access.
counts = ds.counts;
disp(counts(1:min(5,height(counts)),:));

% Find cod activity and inspect the first ten sequences.
interesting = ds.findSequences('Species','fish_cod','MinCount',10, ...
    'MaxResults',10);
disp(interesting(:,{'SeqID','DateTimeStart','sequence_length','fish_cod'}));

% Download selected videos and their timestamps (uncomment when needed).
% ids = interesting.SeqID(1:min(2,height(interesting)));
% downloaded = ds.downloadSequence(ids);
% disp(downloaded(:,{'SeqID','Sensor','Kind','Status'}));

% Check locally available files, without downloading missing sequences.
report = ds.validateDataset('Level','quick');
disp(report(:,{'SeqID','Sensor','Kind','Status','Message'}));

% For rigorous validation, use 'standard' or 'deep':
% report = ds.validateSequence(42,'Level','deep');
