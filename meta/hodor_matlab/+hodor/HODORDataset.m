classdef HODORDataset < handle
    %HODORDATASET Native MATLAB interface to the curated HODOR dataset.
    %   ds = hodor.HODORDataset('D:\HODOR')
    %   ds.downloadSequence(42); ds.validateSequence(42);
    properties (SetAccess=private)
        DatasetFolder (1,1) string
        Timeout (1,1) double
        Retries (1,1) double
        AllowNetwork (1,1) logical
    end
    properties (Dependent)
        sequences
        counts
    end
    properties (Access=private)
        CachedSequences table = table()
        CachedCounts table = table()
        CachedSizes table = table()
        SizesAttempted logical = false
    end
    properties (Constant, Access=private)
        SequenceURL = "https://raw.githubusercontent.com/TAWilts/HODOR/main/meta/sequences.csv"
        CameraURL = "https://doi.pangaea.de/10.1594/PANGAEA.980001?format=textfile"
        SonarURL = "https://doi.pangaea.de/10.1594/PANGAEA.980002?format=textfile"
        CountsURL = "https://doi.pangaea.de/10.1594/PANGAEA.980059?format=textfile"
    end
    methods
        function obj = HODORDataset(folder, opts)
            arguments
                folder (1,1) string
                opts.Timeout (1,1) double {mustBePositive} = 180
                opts.Retries (1,1) double {mustBeNonnegative,mustBeInteger} = 4
                opts.AllowNetwork (1,1) logical = true
            end
            obj.DatasetFolder = folder;
            obj.Timeout = opts.Timeout;
            obj.Retries = opts.Retries;
            obj.AllowNetwork = opts.AllowNetwork;
            if ~isfolder(folder), mkdir(folder); end
            if ~isfolder(fullfile(folder,'meta')), mkdir(fullfile(folder,'meta')); end
        end

        function t = get.sequences(obj)
            if isempty(obj.CachedSequences)
                obj.ensureMetadata('sequences.csv',obj.SequenceURL);
                obj.CachedSequences = hodor.internal.readSequences( ...
                    fullfile(obj.DatasetFolder,'meta','sequences.csv'));
            end
            t = obj.CachedSequences;
        end

        function t = get.counts(obj)
            if isempty(obj.CachedCounts)
                obj.ensureMetadata('activity_counts.tsv',obj.CountsURL);
                obj.CachedCounts = hodor.internal.readCounts( ...
                    fullfile(obj.DatasetFolder,'meta','activity_counts.tsv'));
            end
            t = obj.CachedCounts;
        end

        function refreshMetadata(obj, opts)
            %REFRESHMETADATA Explicitly refresh metadata from their sources.
            arguments
                obj
                opts.IncludePangaea (1,1) logical = true
            end
            obj.fetchMetadata('sequences.csv',obj.SequenceURL,true);
            obj.CachedSequences = table();
            if opts.IncludePangaea
                obj.fetchMetadata('activity_counts.tsv',obj.CountsURL,true);
                obj.fetchMetadata('camera_metadata.tsv',obj.CameraURL,true);
                obj.fetchMetadata('sonar_metadata.tsv',obj.SonarURL,true);
                obj.CachedCounts = table();
                obj.CachedSizes = table();
                obj.SizesAttempted = false;
            end
        end

        function t = findSequences(obj, opts)
            %FINDSEQUENCES Filter activity counts by species and date/duration.
            arguments
                obj
                opts.Species (1,1) string = ""
                opts.MinCount (1,1) double = 1
                opts.From = NaT
                opts.To = NaT
                opts.MinDuration (1,1) duration = seconds(0)
                opts.MaxResults (1,1) double {mustBePositive} = Inf
            end
            c = obj.counts;
            keep = c.sequence_length >= opts.MinDuration;
            if strlength(opts.Species)>0
                if ~ismember(opts.Species,string(c.Properties.VariableNames))
                    error('hodor:UnknownSpecies','Unknown species: %s',opts.Species);
                end
                keep = keep & c.(opts.Species)>=opts.MinCount;
            end
            if ~isnat(opts.From)
                lo = opts.From;
                lo.TimeZone = 'UTC';
                keep = keep & c.DateTimeStart >= lo;
            end
            if ~isnat(opts.To)
                hi = opts.To;
                hi.TimeZone = 'UTC';
                keep = keep & c.DateTimeStart <= hi;
            end
            t = c(keep,:);
            if isfinite(opts.MaxResults), t = t(1:min(height(t),floor(opts.MaxResults)),:); end
        end

        function t = info(obj,id)
            id = obj.normalizeIDs(id);
            if numel(id)~=1, error('hodor:InvalidID','info requires one ID.'); end
            t = obj.sequences(obj.sequences.sequenceNo==id,:);
            try
                c = obj.counts;
                t = outerjoin(t,c(c.SeqID==id,:), 'LeftKeys','sequenceNo', ...
                    'RightKeys','SeqID','MergeKeys',true);
            catch ME
                warning('hodor:CountsUnavailable','Activity counts unavailable: %s',ME.message);
            end
        end

        function result = downloadSequence(obj, ids, opts)
            arguments
                obj
                ids
                opts.Sensors (1,:) string = ["sonar","cam1","cam2"]
                opts.Force (1,1) logical = false
                opts.Validate (1,1) logical = true
                opts.RetryDelay (1,1) double {mustBeNonnegative} = 5
            end
            result = obj.download(ids,opts.Sensors,opts.Force,opts.Validate,opts.RetryDelay);
        end

        function result = downloadVideo(obj,ids,opts)
            arguments
                obj
                ids
                opts.Force (1,1) logical = false
                opts.Validate (1,1) logical = true
            end
            result = obj.download(ids,["cam1","cam2"],opts.Force,opts.Validate,5);
        end

        function result = downloadSonar(obj,ids,opts)
            arguments
                obj
                ids
                opts.Force (1,1) logical = false
                opts.Validate (1,1) logical = true
            end
            result = obj.download(ids,"sonar",opts.Force,opts.Validate,5);
        end

        function report = validateSequence(obj,id,opts)
            arguments
                obj
                id
                opts.Level (1,1) string = "standard"
                opts.Sensors (1,:) string = ["sonar","cam1","cam2"]
                opts.SaveReport (1,1) logical = false
            end
            report = obj.validateDataset('IDs',id,'Level',opts.Level, ...
                'Sensors',opts.Sensors,'OnlyLocal',false,'SaveReport',opts.SaveReport);
        end

        function report = validateDataset(obj,opts)
            arguments
                obj
                opts.IDs double = []
                opts.Level (1,1) string = "quick"
                opts.Sensors (1,:) string = ["sonar","cam1","cam2"]
                opts.OnlyLocal (1,1) logical = true
                opts.SaveReport (1,1) logical = true
            end
            ids = opts.IDs;
            if isempty(ids), ids = obj.sequences.sequenceNo; end
            ids = obj.normalizeIDs(ids);
            sensors = obj.normalizeSensors(opts.Sensors);
            files = hodor.internal.fileManifest(obj.DatasetFolder,obj.sequences,ids,sensors,obj.fileSizes());
            if opts.OnlyLocal
                present = false(height(files),1);
                for k=1:height(files)
                    present(k)=isfile(files.Path(k));
                end
                ids = unique(files.SeqID(present));
                files = files(ismember(files.SeqID,ids),:);
            end
            report = hodor.internal.validateFiles(files,obj.sequences,opts.Level);
            if opts.SaveReport && ~isempty(report)
                reportFolder = fullfile(obj.DatasetFolder,'reports');
                if ~isfolder(reportFolder), mkdir(reportFolder); end
                writetable(report,fullfile(reportFolder,'validation_'+opts.Level+'.csv'));
            end
        end
    end

    methods (Access=private)
        function ids = normalizeIDs(obj,ids)
            arguments
                obj
                ids
            end
            if ~isnumeric(ids) || ~isreal(ids) || ...
                    any(~isfinite(ids(:)) | ids(:)~=floor(ids(:)))
                error('hodor:InvalidID','Sequence IDs must be finite integers.');
            end
            ids = unique(double(ids(:)),'stable');
            if any(~ismember(ids,obj.sequences.sequenceNo))
                error('hodor:UnknownSequence','One or more sequence IDs do not exist.');
            end
        end

        function sensors = normalizeSensors(~,sensors)
            sensors = unique(lower(string(sensors)),'stable');
            if isempty(sensors) || any(~ismember(sensors,["sonar","cam1","cam2"]))
                error('hodor:InvalidSensors','Sensors must be sonar, cam1 and/or cam2.');
            end
        end

        function sizes = fileSizes(obj)
            if ~obj.SizesAttempted
                obj.SizesAttempted = true;
                try
                    obj.ensureMetadata('camera_metadata.tsv',obj.CameraURL);
                    obj.ensureMetadata('sonar_metadata.tsv',obj.SonarURL);
                    obj.CachedSizes = hodor.internal.readFileSizes( ...
                        fullfile(obj.DatasetFolder,'meta','camera_metadata.tsv'), ...
                        fullfile(obj.DatasetFolder,'meta','sonar_metadata.tsv'));
                catch ME
                    warning('hodor:FileSizesUnavailable', ...
                        'PANGAEA byte sizes not available; size checks will be limited: %s',ME.message);
                end
            end
            sizes = obj.CachedSizes;
        end

        function ensureMetadata(obj, filename, url)
            dest = fullfile(obj.DatasetFolder,'meta',filename);
            if ~isfile(dest), obj.fetchMetadata(filename,url,false); end
        end

        function fetchMetadata(obj,filename,url,force)
            if ~obj.AllowNetwork
                error('hodor:Offline','Metadata %s not cached and network disabled.',filename);
            end
            dest = fullfile(obj.DatasetFolder,'meta',filename);
            if ~force && isfile(dest), return; end
            % A failed refresh must preserve the cache and unrelated partials.
            tmp = string(tempname(fileparts(dest)))+".part";
            try
                websave(tmp,url,weboptions('Timeout',obj.Timeout));
                if ~isfile(tmp) || dir(tmp).bytes==0
                    error('hodor:EmptyMetadata','Empty metadata response.');
                end
                % A nonempty HTTP 200 response can still be an error page.
                switch string(filename)
                    case "sequences.csv"
                        hodor.internal.readSequences(tmp);
                    case "activity_counts.tsv"
                        hodor.internal.readCounts(tmp);
                    case {"camera_metadata.tsv","sonar_metadata.tsv"}
                        [~,data] = hodor.internal.readTab(tmp,"SeqID");
                        columns = 10;
                        if string(filename)=="camera_metadata.tsv", columns = 14; end
                        if isempty(data) || size(data,2)~=columns
                            error('hodor:InvalidMetadata','Invalid PANGAEA metadata layout.');
                        end
                end
                movefile(tmp,dest,'f');
            catch ME
                if isfile(tmp), delete(tmp); end
                rethrow(ME)
            end
        end

        function result = download(obj,ids,sensors,force,validate,retryDelay)
            if ~obj.AllowNetwork, error('hodor:Offline','Downloads require network access.'); end
            ids = obj.normalizeIDs(ids);
            sensors = obj.normalizeSensors(sensors);
            files = hodor.internal.fileManifest(obj.DatasetFolder,obj.sequences,ids,sensors,obj.fileSizes());
            n = height(files);
            status = strings(n,1);
            message = strings(n,1);
            for k = 1:n
                fprintf('[%d/%d] Sequence %04d %s %s\n',k,n,files.SeqID(k),files.Sensor(k),files.Kind(k));
                [status(k),message(k)] = hodor.internal.downloadFile( ...
                    files.URL(k),files.Path(k),files.ExpectedBytes(k), ...
                    'Timeout',obj.Timeout,'Retries',obj.Retries, ...
                    'RetryDelay',retryDelay,'Force',force);
                if status(k)=="FAILED"
                    warning('hodor:DownloadFailed','%s: %s',files.Path(k),message(k));
                end
            end
            result = files;
            result.Status = status;
            result.Message = message;
            result.TimeUTC = repmat(string(datetime('now','TimeZone','UTC')),n,1);
            allResults = result;
            reportFolder = fullfile(obj.DatasetFolder,'reports');
            if ~isfolder(reportFolder), mkdir(reportFolder); end
            filename = fullfile(reportFolder,'download_manifest.csv');
            if isfile(filename)
                try
                    previous = readtable(filename,'TextType','string');
                    previous = previous(:,result.Properties.VariableNames);
                    previous.TimeUTC = string(previous.TimeUTC);
                    previous(ismember(previous.Path,result.Path),:) = [];
                    allResults = [previous;result];
                catch ME
                    warning('hodor:ManifestReset','Previous manifest unreadable: %s',ME.message);
                end
            end
            writetable(allResults,filename);
            if validate && n>0
                obj.validateDataset('IDs',ids,'Level','quick', ...
                    'Sensors',sensors,'OnlyLocal',false,'SaveReport',true);
            end
        end
    end
end
