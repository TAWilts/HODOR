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
for key = ["sequenceNo", "sequenceStartUnix", "sequenceEndUnix", "mergingFrames"]
    if ismember(key, header)
        sequences.(key) = str2double(sequences.(key));
    end
end
if any(~isfinite(sequences.sequenceNo)) || numel(unique(sequences.sequenceNo)) ~= height(sequences)
    error('hodor:InvalidMetadata', 'Sequence IDs are invalid or duplicated.');
end
if any(sequences.sequenceEndUnix <= sequences.sequenceStartUnix)
    error('hodor:InvalidMetadata', 'Invalid sequence time interval.');
end
sequences.DateTimeStart = datetime(sequences.sequenceStartUnix, ...
    'ConvertFrom', 'posixtime', 'TimeZone', 'UTC');
sequences.DateTimeEnd = datetime(sequences.sequenceEndUnix, ...
    'ConvertFrom', 'posixtime', 'TimeZone', 'UTC');
sequences.sequence_length = seconds(sequences.sequenceEndUnix-sequences.sequenceStartUnix);
end
