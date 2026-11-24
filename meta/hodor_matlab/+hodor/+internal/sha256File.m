function [hash, bytes] = sha256File(filename)
%SHA256FILE Stream a binary file into SHA-256 using MATLAB's bundled JVM.
arguments
    filename (1,1) string
end
if ~usejava('jvm')
    error('hodor:ChecksumJVM','SHA-256 requires a JVM-enabled MATLAB session.');
end
before = dir(filename);
if ~isscalar(before) || before.isdir || ~isfile(filename)
    error('hodor:ChecksumFile','Not a regular readable file: %s',filename);
end
fid = fopen(filename,'rb');
if fid<0, error('hodor:ChecksumFile','Cannot read %s',filename); end
closeFile = onCleanup(@()fclose(fid)); %#ok<NASGU>
md = javaMethod('getInstance','java.security.MessageDigest','SHA-256');
bytes = 0;
while bytes<before.bytes
    want = min(1024*1024,before.bytes-bytes);
    block = fread(fid,want,'*uint8');
    if numel(block)~=want
        error('hodor:ChecksumRead','Incomplete read: %s',filename);
    end
    md.update(typecast(block(:),'int8'));
    bytes = bytes+numel(block);
end
after = dir(filename);
if ~isscalar(after) || after.bytes~=before.bytes || after.datenum~=before.datenum
    error('hodor:ChecksumChanged','File changed while hashing: %s',filename);
end
digest = typecast(int8(md.digest()),'uint8');
hash = string(lower(reshape(dec2hex(digest,2).',1,[])));
end
