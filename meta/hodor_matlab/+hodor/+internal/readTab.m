function [header, values] = readTab(filename, firstColumn)
%READTAB Read plain TSV and PANGAEA textfile TSV (with comment preamble).
% The returned values are strings to preserve IDs, paths and precision.
arguments
    filename (1,1) string
    firstColumn (1,1) string
end
if ~isfile(filename)
    error('hodor:MetadataMissing', 'Metadata file not found: %s', filename);
end
lines = readlines(filename);
marker = firstColumn + sprintf('\t');
start = find(startsWith(lines, marker) | lines == firstColumn, 1, 'first');
if isempty(start)
    error('hodor:InvalidMetadata', 'Could not find %s header in %s', firstColumn, filename);
end
header = split(lines(start), sprintf('\t')).';
body = lines(start+1:end);
body = body(strlength(strtrim(body)) > 0);
ncol = numel(header);
values = strings(numel(body), ncol);
for k = 1:numel(body)
    fields = split(body(k), sprintf('\t'));
    if numel(fields) ~= ncol
        error('hodor:InvalidMetadata', ...
            'Line %d of %s has %d columns (expected %d).', start+k, filename, numel(fields), ncol);
    end
    values(k, :) = fields.';
end
end
