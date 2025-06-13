function viewSequence(seqNo, datasetPath, showPlot)
% VIEWSEQUENCE Visualizes and compiles a video sequence from sonar and camera data.
%
%   viewSequence(seqNo, datasetPath, showPlot) loads and synchronizes video
%   and timestamp data from a dataset and compiles them into a combined
%   visualization video.
%
%   Inputs:
%       seqNo        - (optional) Integer sequence number to visualize. Default = 12.
%       datasetPath  - (optional) Path to dataset directory. Default = user selection via dialog.
%       showPlot     - (optional) Boolean flag to display frames during processing. Default = false.
%
%   Output:
%       A compiled video file named "sequence_<seqNo>.mp4" is saved to the current directory.

% Handle optional arguments
arguments
    seqNo = 12
    datasetPath = uigetdir()
    showPlot = false
end

% Load metadata CSV file
metaFile = fullfile(datasetPath, "meta", "sequences.csv");
T = readtable(metaFile);

% Find row index for the requested sequence number
seqNoIdx = find(T.sequenceNo == seqNo);

% Construct full file paths to the video files for sonar and both cameras
sonarVideoPath = fullfile(datasetPath, T.('sonarFilePath'){seqNoIdx});
cam1VideoPath = fullfile(datasetPath, T.('cam1FilePath'){seqNoIdx});
cam2VideoPath = fullfile(datasetPath, T.('cam2FilePath'){seqNoIdx});

% Create VideoReader objects to read video frames
sonarVidObj = VideoReader(sonarVideoPath);
cam1VidObj = VideoReader(cam1VideoPath);
cam2VidObj = VideoReader(cam2VideoPath);

% Construct full paths to timestamp files
sonarTSPath = fullfile(datasetPath, T.('sonarFileTimestampsPath'){seqNoIdx});
cam1TSPath = fullfile(datasetPath, T.('cam1FileTimestampsPath'){seqNoIdx});
cam2TSPath = fullfile(datasetPath, T.('cam2FileTimestampsPath'){seqNoIdx});

% Load and convert timestamps to double
sonarTS = double(readlines(sonarTSPath));
cam1TS = double(readlines(cam1TSPath));
cam2TS = double(readlines(cam2TSPath));

% Define the time interval between frames in seconds
updateTime = 0.05;

% Determine the global time range across all sources
startTime = min([sonarTS; cam1TS; cam2TS]) - updateTime;
endTime = max([sonarTS; cam1TS; cam2TS]);
timeVector = startTime:updateTime:endTime;

% Initialize frame pointers for each video stream
sonarPtr = 1;
cam1Ptr = 1;
cam2Ptr = 1;

% Setup output video writer
vw = VideoWriter(sprintf("sequence_%05d.mp4", seqNo), "MPEG-4");
vw.FrameRate = 1 / updateTime;
open(vw);

% Define standard image size for resizing frames
subImageSize = [600, 800];

% Initialize empty placeholder frames
sonarFrame = imresize(uint8(zeros(10, 10, 3)), subImageSize);
sonarCRFrame = imresize(uint8(zeros(10, 10, 3)), subImageSize);  % Close-range sonar view
cam1Frame = imresize(uint8(zeros(10, 10, 3)), subImageSize);
cam2Frame = imresize(uint8(zeros(10, 10, 3)), subImageSize);

% Loop through each timestamp in the unified timeline
for i = 1:numel(timeVector)
    % Load sonar frame closest to current time
    while sonarPtr < numel(sonarTS) && sonarTS(sonarPtr) < timeVector(i)
        sonarPtr = sonarPtr + 1;
        if hasFrame(sonarVidObj)
            rawSonarFrame = im2gray(readFrame(sonarVidObj));
            sonarFrame = insertText(imresize(rawSonarFrame, subImageSize), ...
                [subImageSize(2)/2, subImageSize(1)-20], "Sonar", "FontSize", 20, "AnchorPoint", "Center");
            sonarCRFrame = insertText(imresize(rawSonarFrame(1100:end,:), subImageSize), ...
                [subImageSize(2)/2, subImageSize(1)-20], "Sonar close range", "FontSize", 20, "AnchorPoint", "Center");
        else
            break
        end
    end

    % Load camera 1 frame closest to current time
    while cam1Ptr < numel(cam1TS) && cam1TS(cam1Ptr) < timeVector(i)
        cam1Ptr = cam1Ptr + 1;
        if hasFrame(cam1VidObj)
            rawCam1Frame = im2gray(readFrame(cam1VidObj));
            cam1Frame = insertText(imresize(rawCam1Frame, subImageSize), ...
                [subImageSize(2)/2, subImageSize(1)-20], "Cam 1", "FontSize", 20, "AnchorPoint", "Center");
        else
            break
        end
    end

    % Load camera 2 frame closest to current time
    while cam2Ptr < numel(cam2TS) && cam2TS(cam2Ptr) < timeVector(i)
        cam2Ptr = cam2Ptr + 1;
        if hasFrame(cam2VidObj)
            rawCam2Frame = im2gray(readFrame(cam2VidObj));
            cam2Frame = insertText(imresize(rawCam2Frame, subImageSize), ...
                [subImageSize(2)/2, subImageSize(1)-20], "Cam 2", "FontSize", 20, "AnchorPoint", "Center");
        else
            break
        end
    end

    % Create frame timestamp string for overlay
    videoTimestampString = sprintf("sequence: %d\nunix time: %f\ndate:%s", ...
        seqNo, timeVector(i), datetime(timeVector(i), 'ConvertFrom', 'posixtime', 'Format', 'yyyy-MM-dd''T''HH:mm:ss.SSS'));

    % Combine all frames into a 2x2 grid
    frame = [cam2Frame, cam1Frame; sonarFrame, sonarCRFrame];

    % Overlay timestamp text on the combined frame
    frame = insertText(frame, [subImageSize(2), subImageSize(1)], videoTimestampString, ...
        "FontSize", 20, "AnchorPoint", "Center");

    % Optionally show the frame
    if showPlot
        imshow(frame)
        drawnow
    end

    % Print progress every 100 frames
    if ~mod(i, 100)
        fprintf("at timestamp %fs from %fs (%05.1f%%)\n", ...
            timeVector(i)-timeVector(1), timeVector(end)-timeVector(1), i/numel(timeVector)*100);
    end

    % Write current frame to output video
    writeVideo(vw, frame)
end

% Finalize and close the video file
close(vw)
end
