function [status,message,resultPath,rawPath] = processOneFile(file,scratch,resultsFolder,processor,download)
%PROCESSONEFILE Transactional per-file processing in private scratch.
% Caller owns an empty scratch directory and runs a single writer.
arguments
    file table
    scratch (1,1) string
    resultsFolder (1,1) string
    processor (1,1) function_handle
    download (1,1) function_handle
end
assert(height(file)==1,'Expected one manifest row.');
[~,stem,ext] = fileparts(file.RelativePath);
name = stem+string(ext);
assert(~isempty(regexp(char(name),'^(sonar|cam[12])_[0-9]{4}\.(mp4|txt)$','once')), ...
    'Invalid file name.');
rawPath = fullfile(scratch,name);
resultPath = fullfile(resultsFolder,name+".mat");
status = "FAILED";
message = "";
tmp = "";
try
    if isfile(resultPath)
        saved = load(resultPath,'source');
        if ~isfield(saved,'source') || ...
                ~isequal(saved.source.RelativePath,file.RelativePath) || ...
                ~isequal(saved.source.URL,file.URL)
            error('hodor:ProcessingResult','Existing result has unexpected source metadata.');
        end
        contents = whos('-file',resultPath);
        if ~ismember('result',{contents.name})
            error('hodor:ProcessingResult','Existing MAT file has no processing result.');
        end
        status = "SKIPPED";
        message = "Previously saved result";
        rawPath = "";
        return
    end
    if isfile(rawPath) || isfile(rawPath+".part") || isfolder(rawPath)
        error('hodor:ProcessingScratch','Scratch path already exists; refusing to reuse or delete it.');
    end
    file.Path = rawPath;
    [transport,detail] = download(file);
    if transport~="DOWNLOADED"
        message = "Download failed: "+detail;
        return
    end
    if ~isfile(rawPath) || dir(rawPath).bytes==0 || isfile(rawPath+".part")
        error('hodor:ProcessingInput','Download incomplete or empty.');
    end
    if isfinite(file.ExpectedBytes) && dir(rawPath).bytes~=file.ExpectedBytes
        error('hodor:ProcessingInput','Input differs from published byte count.');
    end
    result = processor(file); %#ok<NASGU>
    source = file(:,{'SeqID','Sensor','Kind','RelativePath','URL'}); %#ok<NASGU>
    tmp = string(tempname(resultsFolder))+".mat";
    save(tmp,'result','source','-v7.3');
    % Do not delete input until result publication succeeds.
    if isfile(resultPath)
        error('hodor:ProcessingResult','Result appeared during processing; refusing overwrite.');
    end
    [ok,why] = movefile(tmp,resultPath);
    if ~ok, error('hodor:ProcessingResult','Cannot publish result: %s',why); end
    tmp = "";
    % Delete exactly the downloaded file, never an existing dataset or folder.
    delete(rawPath);
    if isfile(rawPath)
        error('hodor:ProcessingCleanup','Result saved, but raw file could not be deleted.');
    end
    rawPath = "";
    status = "PROCESSED";
    message = "Result saved; scratch input deleted";
catch ME
    if strlength(tmp)>0 && isfile(tmp), delete(tmp); end
    message = string(ME.message);
end
end
