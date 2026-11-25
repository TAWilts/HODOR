function files = fileManifest(root, sequences, ids, sensors, sizes)
%FILEMANIFEST Six canonical files per sequence, or chosen sensor subset.
arguments
    root (1,1) string
    sequences table
    ids (:,1) double
    sensors (1,:) string
    sizes table = table()
end
names = ["sonar", "cam1", "cam2"];
paths = ["sonarFilePath", "cam1FilePath", "cam2FilePath"];
times = ["sonarFileTimestampsPath", "cam1FileTimestampsPath", "cam2FileTimestampsPath"];
sizeNames = ["sonar", "cam1", "cam2"];
files = table('Size',[numel(ids)*2*numel(sensors),8], ...
    'VariableTypes',{'double','string','string','string','string','string','double','double'}, ...
    'VariableNames',{'SeqID','Sensor','Kind','RelativePath','Path','URL','ExpectedBytes','SequenceDuration'});
entry = 0;
for id = ids.'
    r = find(sequences.sequenceNo == id,1);
    if isempty(r), error('hodor:UnknownSequence', 'Unknown sequence ID: %d.', id); end
    sz = [];
    if ~isempty(sizes)
        si = find(sizes.SeqID == id,1);
        if ~isempty(si), sz = sizes(si,:); end
    end
    for s = 1:3
        if ~ismember(names(s),sensors), continue; end
        for kind = ["Video", "Timestamp"]
            field = paths(s);
            if kind=="Timestamp", field = times(s); end
            column = sequences.(field);
            rel = string(column(r));
            if ismissing(rel) || strlength(rel)==0
                error('hodor:InvalidMetadata','Empty file path for sequence %d.',id);
            end
            % Reject absolute paths and traversal from untrusted metadata.
            rel = replace(rel, "\", "/");
            if startsWith(rel,"/") || contains(rel,"../") || contains(rel,":")
                error('hodor:InvalidMetadata','Unsafe sequence path: %s',rel);
            end
            [~,base,ext] = fileparts(rel);
            if kind=="Video" && ~strcmpi(ext,'.mp4') || ...
                    kind=="Timestamp" && ~strcmpi(ext,'.txt')
                error('hodor:InvalidMetadata','Unexpected file extension: %s',rel);
            end
            if ~strcmp(base+string(ext),names(s)+"_"+compose('%04d',id)+string(ext))
                error('hodor:InvalidMetadata','Unexpected filename for sequence %d: %s',id,rel);
            end
            subset = "980001";
            if names(s)=="sonar", subset = "980002"; end
            url = "https://download.pangaea.de/dataset/"+subset+"/files/"+base+ext;
            expected = NaN;
            if ~isempty(sz)
                expected = sz.(sizeNames(s)+kind+"Bytes");
            end
            destination = fullfile(root, strrep(rel,'/',filesep));
            newRow = {id,names(s),kind,rel,string(destination),url,expected, ...
                sequences.sequenceEndUnix(r)-sequences.sequenceStartUnix(r)};
            entry = entry + 1;
            files(entry,:) = newRow;
        end
    end
end
end
