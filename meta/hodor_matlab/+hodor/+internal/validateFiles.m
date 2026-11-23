function report = validateFiles(files, sequences, level)
%VALIDATEFILES Validate file completeness, time data and decodable frames.
% Quick: file existence and exact published byte sizes (when available).
% Standard: + timestamp consistency, sample decoding and temporal overlap.
% Deep: + full decoding, frame-count match and brightness/entropy metrics.
arguments
    files table
    sequences table
    level (1,1) string {mustBeMember(level,["quick","standard","deep"])}
end
n = height(files);
report = table('Size',[n,12], 'VariableTypes', ...
    {'double','string','string','string','string','double','double', ...
     'double','double','double','double','string'}, ...
    'VariableNames',{'SeqID','Sensor','Kind','Path','Status','Bytes', ...
     'ExpectedBytes','Frames','TimestampCount','MeanBrightness','MeanEntropy','Message'});
report.SeqID = files.SeqID;
report.Sensor = files.Sensor;
report.Kind = files.Kind;
report.Path = files.Path;
report.Status(:) = "PASS";
report.ExpectedBytes = files.ExpectedBytes;
report.Bytes(:) = NaN;
report.Frames(:) = NaN;
report.TimestampCount(:) = NaN;
report.MeanBrightness(:) = NaN;
report.MeanEntropy(:) = NaN;
report.Message(:) = "";
timestamps = cell(n,1);
for k = 1:n
    path = files.Path(k);
    if ~isfile(path)
        report = flag(report,k,"FAIL","File is missing");
        continue
    end
    stat = dir(path);
    report.Bytes(k) = stat.bytes;
    if stat.bytes == 0
        report = flag(report,k,"FAIL","File is empty");
        continue
    end
    if isfinite(files.ExpectedBytes(k)) && stat.bytes~=files.ExpectedBytes(k)
        report = flag(report,k,"FAIL",sprintf( ...
            'Size mismatch: %d vs %.0f expected bytes',stat.bytes,files.ExpectedBytes(k)));
        continue
    elseif ~isfinite(files.ExpectedBytes(k))
        report = flag(report,k,"WARN","Published file size unavailable; integrity not proven");
    end
    if level=="quick", continue; end
    if files.Kind(k)=="Timestamp"
        try
            ts = readlines(path);
            ts = ts(strlength(strtrim(ts))>0);
            values = str2double(ts);
            if isempty(values) || any(~isfinite(values))
                report = flag(report,k,"FAIL","Invalid or empty timestamp series");
                continue
            end
            report.TimestampCount(k) = numel(values);
            if any(diff(values)<0)
                report = flag(report,k,"FAIL","Timestamps run backwards");
                continue
            end
            if any(diff(values)==0)
                report = flag(report,k,"WARN","Duplicate timestamps");
            end
            timestamps{k} = values;
            row = find(sequences.sequenceNo==files.SeqID(k),1);
            tolerance = max(5,0.05*files.SequenceDuration(k));
            if values(1) < sequences.sequenceStartUnix(row)-tolerance || ...
               values(end) > sequences.sequenceEndUnix(row)+tolerance
                report = flag(report,k,"WARN","Timestamps outside sequence metadata range");
            end
            if numel(values)>2
                dt = diff(values);
                good = dt(dt>0);
                if ~isempty(good) && any(dt>max(1.0,5*median(good)))
                    report = flag(report,k,"WARN","Large inter-frame timestamp gap");
                end
            end
        catch ME
            report = flag(report,k,"FAIL","Timestamp read failed: "+string(ME.message));
        end
    else
        try
            reader = VideoReader(path);
            if ~isfinite(reader.Duration) || reader.Duration<=0
                report = flag(report,k,"FAIL","Video has invalid duration");
                continue
            end
            if level=="standard"
                % Three independently decoded positions: beginning/middle/end.
                points = [0,0.5,0.95]*max(0,reader.Duration-1/max(reader.FrameRate,1));
                sampled = 0;
                for t = points
                    reader.CurrentTime = t;
                    if ~hasFrame(reader), error('hodor:VideoDecode','No frame at %.3fs',t); end
                    readFrame(reader);
                    sampled = sampled+1;
                end
                report.Frames(k) = sampled; % Sample frames, not total frames.
            else
                frameCount = 0;
                avgMean = 0;
                avgEntropy = 0;
                black = 0;
                bright = 0;
                noisy = 0;
                while hasFrame(reader)
                    frame = readFrame(reader);
                    gray = double(frame);
                    if size(gray,3)>1
                        gray = 0.2989*gray(:,:,1)+0.5870*gray(:,:,2)+0.1140*gray(:,:,3);
                    end
                    mu = mean(gray(:));
                    h = histcounts(gray(:),0:256);
                    p = h(h>0)/numel(gray);
                    e = -sum(p.*log2(p));
                    frameCount = frameCount+1;
                    avgMean = avgMean+(mu-avgMean)/frameCount;
                    avgEntropy = avgEntropy+(e-avgEntropy)/frameCount;
                    black = black+(mu<45);
                    bright = bright+(mu>200);
                    noisy = noisy+(e>7.5);
                end
                if frameCount==0
                    report = flag(report,k,"FAIL","No decodable video frames");
                else
                    report.Frames(k) = frameCount;
                    report.MeanBrightness(k) = avgMean;
                    report.MeanEntropy(k) = avgEntropy;
                    if black>0 || bright>0 || noisy>0
                        report = flag(report,k,"WARN",sprintf( ...
                            'Quality outliers: %d dark, %d bright, %d high entropy frames', ...
                            black,bright,noisy));
                    end
                end
            end
        catch ME
            report = flag(report,k,"FAIL","Video decode failed: "+string(ME.message));
        end
    end
end
if level=="quick", return; end
% Check each video/sidecar pair. Different sensors legitimately have
% different frame rates, so compare counts only within one sensor.
for k = 1:n
    if files.Kind(k)~="Video" || report.Status(k)=="FAIL", continue; end
    ti = find(files.SeqID==files.SeqID(k) & files.Sensor==files.Sensor(k) ...
        & files.Kind=="Timestamp",1);
    if isempty(ti) || isempty(timestamps{ti}), continue; end
    try
        reader = VideoReader(files.Path(k));
        span = timestamps{ti}(end)-timestamps{ti}(1);
        if abs(reader.Duration-span)>max(5,0.05*span)
            report = flag(report,k,"WARN","Video duration differs from timestamp span");
        end
        if level=="deep" && isfinite(report.Frames(k)) ...
                && abs(report.Frames(k)-numel(timestamps{ti}))>1
            report = flag(report,k,"WARN",sprintf( ...
                'Decoded frames (%d) differ from timestamp count (%d)', ...
                report.Frames(k),numel(timestamps{ti})));
        end
    catch ME
        report = flag(report,k,"WARN","Video/timestamp comparison failed: "+string(ME.message));
    end
end
% Cross-sensor synchronization is measured by temporal coverage, not by
% comparing frame indices from sensors with different sample rates.
for id = unique(files.SeqID).'
    idx = find(files.SeqID==id & files.Kind=="Timestamp");
    idx = idx(~cellfun(@isempty,timestamps(idx)));
    if numel(idx)<2, continue; end
    t0 = zeros(numel(idx),1);
    t1 = zeros(numel(idx),1);
    for j=1:numel(idx)
        t0(j) = timestamps{idx(j)}(1);
        t1(j) = timestamps{idx(j)}(end);
    end
    if max(t0)>min(t1)
        for j=1:numel(idx)
            report = flag(report,idx(j),"WARN","No common temporal overlap between sensors");
        end
    end
end
end

function report = flag(report,k,status,message)
if report.Status(k)~="FAIL"
    if status=="FAIL" || report.Status(k)=="PASS"
        report.Status(k) = status;
    end
end
if strlength(report.Message(k))>0
    report.Message(k) = report.Message(k)+"; "+message;
else
    report.Message(k) = message;
end
end
