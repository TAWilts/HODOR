function sequences = readSequences(filename)
%READSEQUENCES Parse the canonical HODOR sequences.csv (actually TSV).
[header, data] = hodor.internal.readTab(string(filename), "sequenceNo");
required = ["sequenceNo", "sequenceStartUnix", "sequenceEndUnix", ...
    "sonarFilePath", "sonarFileTimestampsPath", ...
    "cam1FilePath", "cam1FileTimestampsPath", ...
    "cam2FilePath", "cam2FileTimestampsPath"];
if ~all(ismember(required, header))
    error('hodor:InvalidMetadata', 'HODOR sequences.csv lacks required columns.');
end
sequences = array2table(data, 'VariableNames', cellstr(header));
% mergingFrames can contain semicolon-separated frame lists; preserve text.
for key = ["sequenceNo", "sequenceStartUnix", "sequenceEndUnix"]
    if ismember(key, header)
        sequences.(key) = str2double(sequences.(key));
    end
end
ids = sequences.sequenceNo;
if isempty(ids) || any(~isfinite(ids) | ids~=floor(ids) | ids<0 | ids>5849) || ...
        numel(unique(ids)) ~= height(sequences)
    error('hodor:InvalidMetadata', 'Sequence IDs are invalid or duplicated.');
end
if any(~isfinite(sequences.sequenceStartUnix) | ~isfinite(sequences.sequenceEndUnix) | ...
        sequences.sequenceEndUnix <= sequences.sequenceStartUnix)
    error('hodor:InvalidMetadata', 'Invalid sequence time interval.');
end
sequences.DateTimeStart = datetime(sequences.sequenceStartUnix, ...
    'ConvertFrom', 'posixtime', 'TimeZone', 'UTC');
sequences.DateTimeEnd = datetime(sequences.sequenceEndUnix, ...
    'ConvertFrom', 'posixtime', 'TimeZone', 'UTC');
sequences.sequence_length = seconds(sequences.sequenceEndUnix-sequences.sequenceStartUnix);
end
