function sizes = readFileSizes(cameraFile, sonarFile)
%READFILESIZES Read exact byte counts from PANGAEA camera/sonar tables.
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
    sizes.(name) = str2double(camera(:,col+1));
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
sizes.sonarVideoBytes = str2double(sonar(:,7));
sizes.sonarTimestampBytes = str2double(sonar(:,9));
if any(sonar(:,6) ~= "sonar_" + compose('%04d',sid) + ".mp4") || ...
   any(sonar(:,8) ~= "sonar_" + compose('%04d',sid) + ".txt")
    error('hodor:InvalidMetadata', 'Unexpected sonar filenames in PANGAEA table.');
end
if any(any(~isfinite(sizes{:,2:end}) | sizes{:,2:end}<=0))
    error('hodor:InvalidMetadata', 'PANGAEA file sizes are missing or invalid.');
end
end
