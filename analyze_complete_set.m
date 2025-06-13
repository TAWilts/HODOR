%% Dataset Consistency Check Script
% This script checks the consistency of a dataset consisting of synchronous sonar
% and stereo camera recordings. It performs the following checks:
% 1. Reads the meta file (sequences.csv) and verifies that all listed files exist and
%    have a size > 0.
% 2. For each video (sonar, camera1, camera2), it checks each frame for abnormalities
%    (extremely dark, extremely bright, or very noisy frames).
% 3. It verifies that in the directories "dataset\Sonar\sequences" and
%    "dataset\Camera\sequences" all referenced files are present.
%
% Adjust the brightness and noise thresholds as needed for your dataset.

%% Parameters and Settings
datasetPath = "D:\datasetNew";

% Path check
if ~isfolder(datasetPath)
    error("%s is not a valid folder",datasetPath)
end

metaFile = fullfile(datasetPath,"meta","sequences.csv");

resPath  = fullfile(datasetPath,"analysis");
resFile = fullfile(resPath,"errorLog.txt");
stateFile = fullfile(resPath,"stateLog.txt");
if ~isfolder(resPath)
    mkdir(resPath);
end
state = struct("lastSequence", 1,"elapsedTime", 0);
if ~isfile(stateFile)
    writelines(jsonencode(state,PrettyPrint=true),stateFile)
else
    state = jsondecode(strjoin(readlines(stateFile)));
end

l = analyzeLogger(resFile);

if state.lastSequence == 1
    l.reset();
end



% Thresholds for image analysis (customize as needed)
thresholdBlack = [45,45,45];   % frames with a mean brightness below this value are considered "almost black"
thresholdBright = [200,200,200]; % frames with a mean brightness above this value are considered "extremely bright"
thresholdNoise = [7.15,7.5,7.5];  % frames with an entropy above this value are considered "very noisy"

%% 1. Read the Meta File
if ~isfile(metaFile)
    error('Meta file %s not found.', metaFile);
end
T = readtable(metaFile);

%% 2. Check Existence and Size of Files Listed in the Meta File
fileFields = {'sonarFilePath','sonarFileTimestampsPath','cam1FilePath','cam1FileTimestampsPath','cam2FilePath','cam2FileTimestampsPath'};
sumStorage = 0;
fprintf('Checking if all files listed in the meta file exist and have a size > 0...\n');
videoFields = {'sonarFilePath', 'cam1FilePath', 'cam2FilePath'};

state.filesizePerSensor = zeros(height(T),length(videoFields));
state.durationPerSensor = zeros(height(T),length(videoFields));
state.expDurationPerSensor = zeros(height(T),length(videoFields));
for i = 1:height(T)
    seqNo = T.sequenceNo(i);
    for j = 1:length(fileFields)
        filePath = fullfile(datasetPath,T.(fileFields{j}){i});  % Assuming the paths are stored as strings in the table

        if ~isfile(filePath)
            l.log(sprintf('Sequence %d at %s to %s, dur %s: File not found: %s\n', seqNo,T.sequenceStartDate(i),T.sequenceEndDate(i),T.sequenceEndDate(i)-T.sequenceStartDate(i), filePath),"");
        else
            fileInfo = dir(filePath);
            if fileInfo.bytes == 0
                l.log(sprintf('Sequence %d at %s to %s, dur %s: File is empty: %s\n', seqNo,T.sequenceStartDate(i),T.sequenceEndDate(i),T.sequenceEndDate(i)-T.sequenceStartDate(i), filePath),"");
            end
            sumStorage = sumStorage + fileInfo.bytes;
        end
    end
end

%% 3. Check Video Frames for Abnormalities
videoFields = {'sonarFilePath', 'cam1FilePath', 'cam2FilePath'};

fprintf("Checking data integrity of sequence files...\n")
if ~isfield(state,"meanPerSensor")
    state.meanPerSensor = zeros(height(T),length(videoFields));
    state.varPerSensor = zeros(height(T),length(videoFields));
    state.entPerSensor = zeros(height(T),length(videoFields));
end

processedBytes = 0;

for i = 1:state.lastSequence-1
    for j = 1:length(videoFields)
        videoPath = fullfile(datasetPath,T.(videoFields{j}){i});
        fileInfo = dir(videoPath);
        processedBytes = processedBytes + fileInfo.bytes;
    end
end

for i = state.lastSequence:height(T)
    tic;
    warnBuffer = "";
    seqNo = T.sequenceNo(i);
    fmt = "yyyy_MM_dd_hh_mm_ss";
    date = string(T.sequenceStartDate(i),fmt);
    for j = 1:length(videoFields)

        videoPath = fullfile(datasetPath,T.(videoFields{j}){i});
        fileInfo = dir(videoPath);
        processedBytes = processedBytes + fileInfo.bytes;

        if ~isfile(videoPath)
            % If the file is missing, it has already been reported
            continue;
        end
        try
            vidObj = VideoReader(videoPath);
        catch ME
            warnBuffer = warnBuffer + sprintf('Sequence %d: Could not open video file %s: %s\n', seqNo, videoPath, ME.message);
            continue;
        end
        nFrames =  vidObj.NumFrames;

        state.filesizePerSensor(i,j) = fileInfo.bytes;
        state.durationPerSensor(i,j) = vidObj.Duration;

        videoTimestamp = zeros(nFrames,1);

        entVal = zeros(nFrames,1);
        meanVal = zeros(nFrames,1);
        varVal = zeros(nFrames,1);

        for fi = 1:nFrames
            grayFrame =  im2gray((readFrame(vidObj)));

            videoTimestamp(fi) = vidObj.CurrentTime;
            % Compute metrics for the frame
            entVal(fi) = entropy(grayFrame);
            varVal(fi) = var(single(grayFrame),0,"all");
            meanVal(fi) = mean(grayFrame,"all");

            % Check for "almost black" frames
            if meanVal(fi) < thresholdBlack(j)
                warnBuffer = warnBuffer + sprintf('Sequence %d, date %s at %s, Frame %d (%.3f): Almost black frame (Mean = %.2f).\n', seqNo, date, videoPath, fi,videoTimestamp(fi), meanVal(fi));
                imwrite(grayFrame,fullfile(resPath,sprintf("%s_date%s_seq%ds_frame%d_time%.3f_AlmostBlackFrame%.2f.png",videoFields{j}, date,seqNo, fi,videoTimestamp(fi), meanVal(fi))))
            end
            % Check for "extremely bright" frames
            if meanVal(fi) > thresholdBright(j)
                warnBuffer = warnBuffer + sprintf('Sequence %d, date %s at %s, Frame %d (%.3f): Extremely bright frame (Mean = %.2f).\n', seqNo, date, videoPath, fi,videoTimestamp(fi), meanVal(fi));
                imwrite(grayFrame,fullfile(resPath,sprintf("%s_date%s_seq%d_frame%d_time%.3f_ExtremelyBrightFrame%.2f.png",videoFields{j}, date,seqNo, fi,videoTimestamp(fi), meanVal(fi))))
            end
            % Check for "very noisy" frames (using entropy)
            if entVal(fi) > thresholdNoise(j)
                warnBuffer = warnBuffer + sprintf('Sequence %d, date %s at %s, Frame %d (%.3f): Very noisy frame (Entropy = %.2f).\n', seqNo, date, videoPath, fi,videoTimestamp(fi), entVal(fi));
                imwrite(grayFrame,fullfile(resPath,sprintf("%s_date%s_seq%d_frame%d_time%.3f_VeryNoisyFrame%.2f.png",videoFields{j}, date,seqNo, fi,videoTimestamp(fi), entVal(fi))))
            end

        end
        state.meanPerSensor(i,j) = mean(meanVal);
        state.varPerSensor(i,j) = mean(varVal);
        state.entPerSensor(i,j) = mean(entVal);
    end
    state.lastSequence = i;
    writelines(jsonencode(state,PrettyPrint=true),stateFile)
    state.elapsedTime = state.elapsedTime + toc;
    remainingTime = seconds(state.elapsedTime/(processedBytes)*(sumStorage-processedBytes));
    remainingTime.Format = 'hh:mm:ss';
    runTime = seconds(state.elapsedTime);
    runTime.Format = 'hh:mm:ss';
    msgProg = sprintf('[%s]  progress: %d / %d (%s elapsed, %s remaining)\n', datetime("now"),i, height(T), char(runTime), char(remainingTime));


    l.log(warnBuffer,msgProg);
end

save("dataAnalysis_" + string(datetime("now",'Format','yyyy_MM_dd_HH_mm_ss')) + ".mat")
figStorePath = '';
timestamps = datetime(T.sequenceStartUnix,"ConvertFrom","posixtime");
f = figure;
[hAx,hLine1,hLine2] = plotyy(timestamps,state.meanPerSensor(:,1),timestamps,state.meanPerSensor(:,2:3),"scatter");
hLine1.Marker = ".";
hLine2(1).Marker  = ".";
hLine2(2).Marker  = ".";
hAx(1).YLabel.String = 'Mean Sonar';
hAx(2).YLabel.String = 'Mean Camera';
xlabel('Date');
% ylabel('Mean');
title('Avg. mean per sequence');
grid on;
legend("son","cam1","cam2")
storeInAllFormats(f,figStorePath,'Mean')

f = figure;
[hAx,hLine1,hLine2] = plotyy(timestamps,state.varPerSensor(:,1),timestamps,state.varPerSensor(:,2:3),"scatter");
hLine1.Marker = ".";
hLine2(1).Marker  = ".";
hLine2(2).Marker  = ".";
hAx(1).YLabel.String = 'Variance Sonar';
hAx(2).YLabel.String = 'Variance Camera';
xlabel('Date');
% ylabel('Var');
title('Avg. variance per sequence');
grid on;
legend("son","cam1","cam2")
storeInAllFormats(f,figStorePath,'Variance')

f = figure;
[hAx,hLine1,hLine2] = plotyy(timestamps,state.entPerSensor(:,1),timestamps,state.entPerSensor(:,2:3),"scatter");
hLine1.Marker = ".";
hLine2(1).Marker  = ".";
hLine2(2).Marker  = ".";
hAx(1).YLabel.String = 'Entropy Sonar';
hAx(2).YLabel.String = 'Entropy Camera';
xlabel('Date');
% ylabel('Entropy');
title('Avg. entropy per sequence');
grid on;
legend("son","cam1","cam2")
storeInAllFormats(f,figStorePath,'Entropy')

figStorePath = '';
timestamps = datetime(T.sequenceStartUnix,"ConvertFrom","posixtime");
f = figure;
[hAx,hLine1,hLine2] = plotyy(timestamps,state.filesizePerSensor(:,1),timestamps,state.filesizePerSensor(:,2:3),"scatter");
hLine1.Marker = ".";
hLine2(1).Marker  = ".";
hLine2(2).Marker  = ".";
hAx(1).YLabel.String = 'Size Sonar';
hAx(2).YLabel.String = 'Size Camera';
xlabel('Date');
% ylabel('Mean');
title('Size per sequence');
grid on;
legend("son","cam1","cam2")
storeInAllFormats(f,figStorePath,'fileSize')

timestamps = datetime(T.sequenceStartUnix,"ConvertFrom","posixtime");
f = figure;
[hAx,hLine1,hLine2] = plotyy(timestamps,state.durationPerSensor(:,1),timestamps,state.durationPerSensor(:,2:3),"scatter");
hLine1.Marker = ".";
hLine2(1).Marker  = ".";
hLine2(2).Marker  = ".";
hAx(1).YLabel.String = 'Dur Sonar';
hAx(2).YLabel.String = 'Dur Camera';
xlabel('Date');
% ylabel('Mean');
title('Dur per sequence');
grid on;
legend("son","cam1","cam2")
storeInAllFormats(f,figStorePath,'duration')


%% 4. Check Directory Consistency
% Collect all files referenced in the meta file
expectedFiles = {};
for i = 1:height(T)
    for j = 1:length(fileFields)
        expectedFiles{end+1} = fullfile(datasetPath,T.(fileFields{j}){i});  %#ok<SAGROW>
    end
end

% Check in the Sonar directory
sonarDir = fullfile(datasetPath,'dataset', 'Sonar', 'sequences');
allSonarFiles = dir(fullfile(sonarDir, '**', '*.*'));
allSonarFiles = allSonarFiles(~[allSonarFiles.isdir]);
fprintf('\nChecking consistency in the Sonar directory...\n');
for k = 1:length(allSonarFiles)
    fullPath = fullfile(allSonarFiles(k).folder, allSonarFiles(k).name);
    % Normalize path (adjust for Windows if needed)
    fullPathNorm = strrep(fullPath, '/', filesep);
    % Report if the file is not referenced in the meta file
    if ~any(strcmp(expectedFiles, fullPathNorm))
        fprintf('Unreferenced file found in Sonar directory: %s\n', fullPathNorm);
    end
end

% Check in the Camera directory
cameraDir = fullfile(datasetPath,'dataset', 'Camera', 'sequences');
allCameraFiles = dir(fullfile(cameraDir, '**', '*.*'));
allCameraFiles = allCameraFiles(~[allCameraFiles.isdir]);
fprintf('\nChecking consistency in the Camera directory...\n');
for k = 1:length(allCameraFiles)
    fullPath = fullfile(allCameraFiles(k).folder, allCameraFiles(k).name);
    fullPathNorm = strrep(fullPath, '/', filesep);
    if ~any(strcmp(expectedFiles, fullPathNorm))
        fprintf('Unreferenced file found in Camera directory: %s\n', fullPathNorm);
    end
end

fprintf('\nDataset consistency check completed.\n');
