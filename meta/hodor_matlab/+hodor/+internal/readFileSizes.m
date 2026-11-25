function sizes = readFileSizes(cameraFile, sonarFile)
%READFILESIZES Read exact byte counts where published; rounded sizes are NaN.
% Layout follows the published PANGAEA.980001 and .980002 parameter order.
[~, camera] = hodor.internal.readTab(string(cameraFile), "SeqID");
[~, sonar] = hodor.internal.readTab(string(sonarFile), "SeqID");
if size(camera,2) ~= 14 || size(sonar,2) ~= 10
    error('hodor:InvalidMetadata', 'PANGAEA binary-file metadata layout changed.');
end
sizes = table(str2double(camera(:,1)), 'VariableNames', {'SeqID'});
for j = 1:4
    expected = ["cam1", "cam1", "cam2", "cam2"];
    suffix = ["Video", "Timestamp", "Video", "Timestamp"];
    col = 6 + 2*(j-1);
    name = expected(j) + suffix(j) + "Bytes";
    sizes.(name) = exactBytes(camera(:,col+1));
    % A PANGAEA format change must not silently associate wrong file sizes.
    ext = ".mp4";
    if mod(j,2)==0, ext = ".txt"; end
    expectedFile = expected(j) + "_" + compose('%04d',sizes.SeqID) + ext;
    if any(camera(:,col) ~= expectedFile)
        error('hodor:InvalidMetadata', 'Unexpected camera filenames in PANGAEA table.');
    end
end
sid = str2double(sonar(:,1));
if numel(sid) ~= height(sizes) || ~isequal(sid, sizes.SeqID)
    error('hodor:InvalidMetadata', 'PANGAEA camera/sonar sequence IDs differ.');
end
sizes.sonarVideoBytes = exactBytes(sonar(:,7));
sizes.sonarTimestampBytes = exactBytes(sonar(:,9));
if any(sonar(:,6) ~= "sonar_" + compose('%04d',sid) + ".mp4") || ...
   any(sonar(:,8) ~= "sonar_" + compose('%04d',sid) + ".txt")
    error('hodor:InvalidMetadata', 'Unexpected sonar filenames in PANGAEA table.');
end
end

function bytes = exactBytes(values)
% The live text export uses e.g. "2.5 MBytes" even under a [Bytes] header.
% Those rounded display values cannot support an exact integrity check.
bytes = NaN(size(values));
for k=1:numel(values)
    value = strtrim(values(k));
    token = regexp(char(value),'^(\d+)(?: Bytes)?$','tokens','once');
    if ~isempty(token)
        bytes(k) = str2double(token{1});
        if isfinite(bytes(k)) && bytes(k)>0 && bytes(k)<=flintmax
            continue
        end
    else
        token = regexp(char(value),'^(\d+(?:\.\d+)?) [kMGT]Bytes$','tokens','once');
        if ~isempty(token) && isfinite(str2double(token{1})) && str2double(token{1})>0
            continue
        end
    end
    error('hodor:InvalidMetadata','PANGAEA file size is missing or invalid: %s',value);
end
end
