function [hash, bytes] = sha256File(filename)
%SHA256FILE Hash file bytes using the operating system's SHA-256 utility.
% No JVM, Python, toolbox, or full-file MATLAB allocation is required.
arguments
    filename (1,1) string
end
before = dir(filename);
if ~isscalar(before) || before.isdir || ~isfile(filename)
    error('hodor:ChecksumFile','Not a regular readable file: %s',filename);
end

% Pass the filename as data, not as part of executable shell source.
% Restore the caller's environment even if hashing raises an error.
envName = 'HODOR_SHA256_FILE';
previous = getenv(envName);
restoreEnv = onCleanup(@()setenv(envName,previous)); %#ok<NASGU>
setenv(envName,char(filename));

if ispc
    cmd = ['powershell.exe -NoLogo -NoProfile -NonInteractive -Command ' ...
        '"(Get-FileHash -LiteralPath $env:HODOR_SHA256_FILE -Algorithm SHA256 -ErrorAction Stop).Hash"'];
elseif ismac
    cmd = '/usr/bin/shasum -a 256 < "$HODOR_SHA256_FILE"';
elseif isunix
    cmd = 'sha256sum < "$HODOR_SHA256_FILE"';
else
    error('hodor:ChecksumPlatform','No SHA-256 backend for this operating system.');
end
[status,output] = system(cmd);
if status~=0
    error('hodor:ChecksumBackend','SHA-256 utility failed (exit %d): %s', ...
        status,strtrim(output));
end
% PowerShell prints only the hash. Unix tools also print a stdin marker.
% Reject unexpected or ambiguous output rather than guessing a digest.
token = regexp(strtrim(output),'^([0-9A-Fa-f]{64})(?:[ \t]+\*?-)?$','tokens','once');
if isempty(token)
    error('hodor:ChecksumBackend','SHA-256 utility returned an invalid digest.');
end
after = dir(filename);
if ~isscalar(after) || after.isdir || after.bytes~=before.bytes || after.datenum~=before.datenum
    error('hodor:ChecksumChanged','File changed while hashing: %s',filename);
end
hash = string(lower(token{1}));
bytes = after.bytes;
end
