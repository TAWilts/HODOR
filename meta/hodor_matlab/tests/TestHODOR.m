classdef TestHODOR < matlab.unittest.TestCase
    % Offline regressions. Tiny video tests use the local MPEG-4 codec.
    properties
        Folder string
    end
    methods (TestMethodSetup)
        function createFixture(testCase)
            testCase.Folder = string(tempname) + " HODOR QA with spaces";
            mkdir(fullfile(testCase.Folder,'meta'));
            fid = fopen(fullfile(testCase.Folder,'meta','sequences.csv'),'wt');
            fields = ["sequenceNo","sequenceStartUnix","sequenceEndUnix", ...
                "sequenceStartDate","sequenceEndDate", ...
                "sonarFilePath","sonarFileTimestampsPath","mergingFrames", ...
                "cam1FilePath","cam1FileTimestampsPath", ...
                "cam2FilePath","cam2FileTimestampsPath"];
            fprintf(fid,'%s\n',strjoin(fields,sprintf('\t')));
            for id=0:1
                names = compose('%04d',id);
                parts = [string(id),"1629609208.033","1629609281.673", ...
                    "2021-08-22T05:13:28.033","2021-08-22T05:14:41.673", ...
                    "sonar\sonar_"+names+".mp4","sonar\sonar_"+names+".txt", "0", ...
                    "camera\cam1_"+names+".mp4","camera\cam1_"+names+".txt", ...
                    "camera\cam2_"+names+".mp4","camera\cam2_"+names+".txt"];
                fprintf(fid,'%s\n',strjoin(parts,sprintf('\t')));
            end
            fclose(fid);
        end
    end
    methods (TestMethodTeardown)
        function cleanup(testCase)
            if isfolder(testCase.Folder), rmdir(testCase.Folder,'s'); end
        end
    end
    methods (Test)
        function sequencesAreParsed(testCase)
            ds = hodor.HODORDataset(testCase.Folder,'AllowNetwork',false);
            s = ds.sequences;
            testCase.verifyEqual(height(s),2);
            testCase.verifyEqual(s.sequenceNo,[0;1]);
            testCase.verifyLessThan(abs(seconds(s.sequence_length(1))-73.64),0.001);
        end

        function manifestUsesCanonicalNames(testCase)
            ds = hodor.HODORDataset(testCase.Folder,'AllowNetwork',false);
            files = hodor.internal.fileManifest(testCase.Folder,ds.sequences, ...
                [0;1],["cam1","sonar"],table());
            testCase.verifyEqual(height(files),8);
            testCase.verifyTrue(any(endsWith(files.URL, ...
                '/dataset/980002/files/sonar_0000.mp4')));
            testCase.verifyTrue(any(contains(files.Path,'cam1_0001.txt')));
        end

        function pangaeaFileSizes(testCase)
            cam = fullfile(testCase.Folder,'cam.tsv');
            son = fullfile(testCase.Folder,'son.tsv');
            fid = fopen(cam,'wt');
            fprintf(fid,'/* DATA DESCRIPTION:\nfoo\n*/\n');
            fprintf(fid,'%s\n',strjoin(["SeqID","c"+string(2:14)],sprintf('\t')));
            fclose(fid);
            row = ["0","1","2","2021-08-22T05:13:28.033", ...
                "2021-08-22T05:14:41.673","cam1_0000.mp4","11", ...
                "cam1_0000.txt","12","cam2_0000.mp4","13", ...
                "cam2_0000.txt","14","0"];
            fid=fopen(cam,'at'); fprintf(fid,'%s\n',strjoin(row,sprintf('\t'))); fclose(fid);
            fid=fopen(son,'wt');
            fprintf(fid,'%s\n',strjoin(["SeqID", "t1","t2","start","end", ...
                "sonar","bytes","ts","tsbytes","frames"],sprintf('\t')));
            fprintf(fid,'%s\n',strjoin(["0","1","2","start","end", ...
                "sonar_0000.mp4","21","sonar_0000.txt","22","0"],sprintf('\t')));
            fclose(fid);
            sizes = hodor.internal.readFileSizes(cam,son);
            testCase.verifyEqual(sizes.cam1VideoBytes,11);
            testCase.verifyEqual(sizes.sonarTimestampBytes,22);
        end

        function mergingFrameListsArePreserved(testCase)
            % The published TSV contains semicolon-separated frame indices.
            suiteFolder = fileparts(fileparts(mfilename('fullpath')));
            source = fullfile(fileparts(suiteFolder),'sequences.csv');
            path = fullfile(testCase.Folder,'meta','sequences.csv');
            copyfile(source,path);
            sequences = hodor.internal.readSequences(path);
            testCase.verifyClass(sequences.mergingFrames,'string');
            testCase.verifyEqual(sequences.mergingFrames(sequences.sequenceNo==217), ...
                "3689;12126");
            testCase.verifyEqual(sequences.mergingFrames(sequences.sequenceNo==246), ...
                "18;8515");
        end

        function roundedPublishedSizesRemainUnverified(testCase)
            % PANGAEA currently exports display values rather than exact bytes.
            testCase.writeSizeFixtures();
            camera = fullfile(testCase.Folder,'meta','camera_metadata.tsv');
            sonar = fullfile(testCase.Folder,'meta','sonar_metadata.tsv');
            cameraLines = readlines(camera);
            cameraFields = split(cameraLines(3),sprintf('\t'));
            cameraFields([7,9,11,13]) = ["2.5 MBytes","21.7 kBytes", ...
                "1 GBytes","22.3 kBytes"];
            cameraLines(3) = strjoin(cameraFields,sprintf('\t'));
            testCase.writeText(camera,cameraLines);
            sonarLines = readlines(sonar);
            sonarFields = split(sonarLines(3),sprintf('\t'));
            sonarFields(7) = "625.5 kBytes";
            sonarFields(9) = "340 Bytes";
            sonarLines(3) = strjoin(sonarFields,sprintf('\t'));
            testCase.writeText(sonar,sonarLines);
            sizes = hodor.internal.readFileSizes(camera,sonar);
            testCase.verifyTrue(all(isnan(sizes{:,2:6})));
            testCase.verifyEqual(sizes.sonarTimestampBytes,340);
            ds = hodor.HODORDataset(testCase.Folder,'AllowNetwork',false);
            testCase.writeBytes(fullfile(testCase.Folder,'sonar','sonar_0000.mp4'),10);
            report = ds.validateSequence(0,'Level','quick','Sensors','sonar');
            video = report.Kind=="Video";
            testCase.verifyEqual(report.Status(video),"WARN");
            testCase.verifyTrue(isnan(report.ExpectedBytes(video)));
            testCase.verifyTrue(contains(report.Message(video),"Published file size unavailable"));
        end

        function malformedPublishedSizeIsRejected(testCase)
            testCase.writeSizeFixtures();
            camera = fullfile(testCase.Folder,'meta','camera_metadata.tsv');
            sonar = fullfile(testCase.Folder,'meta','sonar_metadata.tsv');
            lines = readlines(camera);
            fields = split(lines(3),sprintf('\t'));
            fields(7) = "not-a-size";
            lines(3) = strjoin(fields,sprintf('\t'));
            testCase.writeText(camera,lines);
            testCase.verifyError(@() hodor.internal.readFileSizes(camera,sonar), ...
                'hodor:InvalidMetadata');
        end

        function countsReadCorrectly(testCase)
            filename = fullfile(testCase.Folder,'meta','activity_counts.tsv');
            columns = ["SeqID", "t1", "t2", "Start", "End", ...
                "c"+string(1:18)];
            data = ["0", "1629609208", "1629609282", ...
                "2021-08-22T05:13:28.033","2021-08-22T05:14:41.673", ...
                string(1:18)];
            fid=fopen(filename,'wt');
            fprintf(fid,'/* PANGAEA header */\n');
            fprintf(fid,'%s\n',strjoin(columns,sprintf('\t')));
            fprintf(fid,'%s\n',strjoin(data,sprintf('\t')));
            fclose(fid);
            ds = hodor.HODORDataset(testCase.Folder,'AllowNetwork',false);
            testCase.verifyEqual(ds.counts.fish_cod,6);
            selected = ds.findSequences('Species','fish_cod','MinCount',5);
            testCase.verifyEqual(selected.SeqID,0);
        end

        function quickValidationDetectsMissingAndEmpty(testCase)
            ds = hodor.HODORDataset(testCase.Folder,'AllowNetwork',false);
            mkdir(fullfile(testCase.Folder,'sonar'));
            fid=fopen(fullfile(testCase.Folder,'sonar','sonar_0000.mp4'),'wb');
            fwrite(fid,ones(1,10,'uint8')); fclose(fid);
            fid=fopen(fullfile(testCase.Folder,'sonar','sonar_0000.txt'),'wt');
            fclose(fid);
            report = ds.validateSequence(0,'Level','quick');
            testCase.verifyEqual(height(report),6);
            video = report(report.Sensor=="sonar" & report.Kind=="Video",:);
            testCase.verifyEqual(video.Status,"WARN"); % No published sizes cached.
            empty = report(report.Sensor=="sonar" & report.Kind=="Timestamp",:);
            testCase.verifyEqual(empty.Status,"FAIL");
            testCase.verifyEqual(sum(report.Status=="FAIL"),5);
            present = ds.validateDataset('Level','quick','SaveReport',false);
            testCase.verifyEqual(unique(present.SeqID),0);
        end

        function unknownIDsAreRejected(testCase)
            ds = hodor.HODORDataset(testCase.Folder,'AllowNetwork',false);
            testCase.verifyError(@() ds.validateSequence(99), 'hodor:UnknownSequence');
        end

        function invalidIDsAreRejected(testCase)
            ds = hodor.HODORDataset(testCase.Folder,'AllowNetwork',false);
            for id = [NaN, Inf, -Inf, 0.5]
                testCase.verifyError(@() ds.info(id),'hodor:InvalidID');
            end
            for id = [-1, 5850]
                testCase.verifyError(@() ds.info(id),'hodor:UnknownSequence');
            end
        end

        function canonicalBoundaryIDsAreAccepted(testCase)
            suiteFolder = fileparts(fileparts(mfilename('fullpath')));
            source = fullfile(fileparts(suiteFolder),'sequences.csv');
            copyfile(source,fullfile(testCase.Folder,'meta','sequences.csv'));
            ds = hodor.HODORDataset(testCase.Folder,'AllowNetwork',false);
            testCase.verifyEqual(ds.sequences.sequenceNo,(0:5849)');
            report = ds.validateDataset('IDs',[0,5849],'Sensors','sonar', ...
                'OnlyLocal',false,'SaveReport',false);
            testCase.verifyEqual(height(report),4);
            testCase.verifyEqual(unique(report.SeqID),[0;5849]);
            testCase.verifyTrue(all(report.Status=="FAIL"));
        end

        function invalidSensorsAreRejected(testCase)
            ds = hodor.HODORDataset(testCase.Folder,'AllowNetwork',false);
            testCase.verifyError(@() ds.validateSequence(0,'Sensors','camera'), ...
                'hodor:InvalidSensors');
            testCase.verifyError(@() ds.validateSequence(0,'Sensors',strings(1,0)), ...
                'hodor:InvalidSensors');
        end

        function missingOfflineMetadataIsExplained(testCase)
            delete(fullfile(testCase.Folder,'meta','sequences.csv'));
            ds = hodor.HODORDataset(testCase.Folder,'AllowNetwork',false);
            testCase.verifyError(@() ds.sequences,'hodor:Offline');
            testCase.verifyError(@() ds.counts,'hodor:Offline');
            testCase.verifyError(@() ds.downloadSonar(0),'hodor:Offline');
        end

        function malformedMetadataIsRejected(testCase)
            path = fullfile(testCase.Folder,'meta','sequences.csv');
            testCase.writeText(path,"<html>upstream error</html>");
            ds = hodor.HODORDataset(testCase.Folder,'AllowNetwork',false);
            testCase.verifyError(@() ds.sequences,'hodor:InvalidMetadata');
            testCase.writeText(path,"sequenceNo" + sprintf('\t') + "sequenceStartUnix" + ...
                newline + "0" + sprintf('\t') + "1");
            testCase.verifyError(@() ds.sequences,'hodor:InvalidMetadata');
        end

        function sequenceMetadataRejectsNonfiniteTimes(testCase)
            path = fullfile(testCase.Folder,'meta','sequences.csv');
            original = readlines(path);
            for column = [2,3]
                for value = ["NaN","Inf","-Inf"]
                    testCase.replaceFixtureField(path,original,column,value);
                    testCase.verifyError(@() hodor.internal.readSequences(path), ...
                        'hodor:InvalidMetadata');
                end
            end
        end

        function sequenceMetadataRejectsInvalidIDs(testCase)
            path = fullfile(testCase.Folder,'meta','sequences.csv');
            original = readlines(path);
            for value = ["NaN","-1","0.5","5850"]
                testCase.replaceFixtureField(path,original,1,value);
                testCase.verifyError(@() hodor.internal.readSequences(path), ...
                    'hodor:InvalidMetadata');
            end
        end

        function fullyCachedMetadataWorksOffline(testCase)
            testCase.writeCountsFixture();
            testCase.writeSizeFixtures();
            ds = hodor.HODORDataset(testCase.Folder,'AllowNetwork',false);
            testCase.verifyEqual(height(ds.sequences),2);
            testCase.verifyEqual(ds.counts.fish_cod,6);
            selected = ds.findSequences('Species','fish_cod','MinCount',5);
            testCase.verifyClass(selected,'table');
            testCase.verifyEqual(selected.SeqID,0);
            testCase.verifyWarningFree(@() ds.validateSequence(0,'Level','quick'));
            testCase.verifyError(@() ds.refreshMetadata(),'hodor:Offline');
        end

        function manifestHandlesSpacesAndSeparators(testCase)
            ds = hodor.HODORDataset(testCase.Folder,'AllowNetwork',false);
            files = hodor.internal.fileManifest(testCase.Folder,ds.sequences, ...
                0,"sonar",table());
            testCase.verifyTrue(contains(testCase.Folder," "));
            testCase.verifyEqual(files.RelativePath(1),"sonar/sonar_0000.mp4");
            testCase.verifyEqual(files.Path(1), ...
                string(fullfile(testCase.Folder,'sonar','sonar_0000.mp4')));
            testCase.verifyFalse(any(contains(files.RelativePath,"\")));
        end

        function quickChecksPublishedSizesAndReportSchema(testCase)
            testCase.writeSizeFixtures();
            ds = hodor.HODORDataset(testCase.Folder,'AllowNetwork',false);
            sizes = hodor.internal.readFileSizes( ...
                fullfile(testCase.Folder,'meta','camera_metadata.tsv'), ...
                fullfile(testCase.Folder,'meta','sonar_metadata.tsv'));
            files = hodor.internal.fileManifest(testCase.Folder,ds.sequences, ...
                0,["sonar","cam1","cam2"],sizes);
            for k = 1:height(files)
                testCase.writeBytes(files.Path(k),files.ExpectedBytes(k));
            end
            report = ds.validateSequence(0,'Level','quick','SaveReport',true);
            testCase.verifyTrue(all(report.Status=="PASS"));
            testCase.verifyEqual(report.Bytes,report.ExpectedBytes);
            testCase.verifyEqual(report.Properties.VariableNames, ...
                {'SeqID','Sensor','Kind','Path','Status','Bytes','ExpectedBytes', ...
                 'Frames','TimestampCount','MeanBrightness','MeanEntropy','Message'});
            testCase.verifyTrue(isfile(fullfile(testCase.Folder,'reports','validation_quick.csv')));
            testCase.writeBytes(files.Path(1),files.ExpectedBytes(1)+1);
            changed = ds.validateSequence(0,'Level','quick');
            testCase.verifyEqual(changed.Status(1),"FAIL");
            testCase.verifyTrue(contains(changed.Message(1),"Size mismatch"));
            testCase.verifyEqual(sum(changed.Status=="PASS"),5);
        end

        function duplicateTimestampsWarn(testCase)
            [files,sequences] = testCase.timestampFixture([0,0.5,0.5,1]);
            report = hodor.internal.validateFiles(files,sequences,"standard");
            testCase.verifyEqual(report.Status,"WARN");
            testCase.verifyTrue(contains(report.Message,"Duplicate timestamps"));
            testCase.verifyEqual(report.TimestampCount,4);
        end

        function backwardsTimestampsFail(testCase)
            [files,sequences] = testCase.timestampFixture([0,1,0.5]);
            report = hodor.internal.validateFiles(files,sequences,"standard");
            testCase.verifyEqual(report.Status,"FAIL");
            testCase.verifyTrue(contains(report.Message,"run backwards"));
        end

        function nonfiniteTimestampsFail(testCase)
            for value = [NaN,Inf,-Inf]
                [files,sequences] = testCase.timestampFixture([0,value,1]);
                report = hodor.internal.validateFiles(files,sequences,"standard");
                testCase.verifyEqual(report.Status,"FAIL");
                testCase.verifyTrue(contains(report.Message,"Invalid or empty timestamp series"));
            end
        end

        function differentSensorSampleRatesAreAccepted(testCase)
            ds = hodor.HODORDataset(testCase.Folder,'AllowNetwork',false);
            sequences = ds.sequences;
            files = hodor.internal.fileManifest(testCase.Folder,sequences, ...
                0,["sonar","cam1"],table());
            files = files(files.Kind=="Timestamp",:);
            offsets = {[0,0.5,1],[0,0.25,0.5,0.75,1]};
            for k = 1:height(files)
                testCase.writeTimestamps(files.Path(k),sequences.sequenceStartUnix(1)+offsets{k});
                stat = dir(files.Path(k));
                files.ExpectedBytes(k) = stat.bytes;
            end
            report = hodor.internal.validateFiles(files,sequences,"standard");
            testCase.verifyTrue(all(report.Status=="PASS"));
            testCase.verifyEqual(report.TimestampCount,[3;5]);
        end

        function sensorsWithoutCommonOverlapWarn(testCase)
            ds = hodor.HODORDataset(testCase.Folder,'AllowNetwork',false);
            sequences = ds.sequences;
            files = hodor.internal.fileManifest(testCase.Folder,sequences, ...
                0,["sonar","cam1"],table());
            files = files(files.Kind=="Timestamp",:);
            offsets = {[0,0.5,1],[2,2.5,3]};
            for k = 1:height(files)
                testCase.writeTimestamps(files.Path(k),sequences.sequenceStartUnix(1)+offsets{k});
                stat = dir(files.Path(k));
                files.ExpectedBytes(k) = stat.bytes;
            end
            report = hodor.internal.validateFiles(files,sequences,"standard");
            testCase.verifyEqual(report.Status,["WARN";"WARN"]);
            testCase.verifyTrue(all(contains(report.Message, ...
                "No common temporal overlap between sensors")));
        end

        function tinyVideoStandardAndDeepDecode(testCase)
            [files,sequences] = testCase.videoFixture(4,100,4);
            standard = hodor.internal.validateFiles(files,sequences,"standard");
            video = standard.Kind=="Video";
            testCase.verifyTrue(all(standard.Status=="PASS"));
            testCase.verifyEqual(standard.Frames(video),3);
            deep = hodor.internal.validateFiles(files,sequences,"deep");
            testCase.verifyTrue(all(deep.Status=="PASS"));
            testCase.verifyEqual(deep.Frames(video),4);
            testCase.verifyEqual(deep.TimestampCount(~video),4);
            testCase.verifyGreaterThan(deep.MeanBrightness(video),45);
            testCase.verifyTrue(isfinite(deep.MeanEntropy(video)));
        end

        function darkTinyVideoWarns(testCase)
            [files,sequences] = testCase.videoFixture(4,0,4);
            report = hodor.internal.validateFiles(files,sequences,"deep");
            video = report.Kind=="Video";
            testCase.verifyEqual(report.Status(video),"WARN");
            testCase.verifyTrue(contains(report.Message(video),"4 dark"));
            testCase.verifyEqual(report.Status(~video),"PASS");
        end

        function overbrightTinyVideoWarns(testCase)
            [files,sequences] = testCase.videoFixture(4,255,4);
            report = hodor.internal.validateFiles(files,sequences,"deep");
            video = report.Kind=="Video";
            testCase.verifyEqual(report.Status(video),"WARN");
            testCase.verifyTrue(contains(report.Message(video),"4 bright"));
            testCase.verifyEqual(report.Status(~video),"PASS");
        end

        function deepDetectsFrameTimestampMismatch(testCase)
            [files,sequences] = testCase.videoFixture(6,100,3);
            report = hodor.internal.validateFiles(files,sequences,"deep");
            video = report.Kind=="Video";
            testCase.verifyEqual(report.Status(video),"WARN");
            testCase.verifyEqual(report.Frames(video),6);
            testCase.verifyTrue(contains(report.Message(video), ...
                "Decoded frames (6) differ from timestamp count (3)"));
        end

        function corruptVideoFailsDecode(testCase)
            ds = hodor.HODORDataset(testCase.Folder,'AllowNetwork',false);
            files = hodor.internal.fileManifest(testCase.Folder,ds.sequences, ...
                0,"sonar",table());
            files = files(files.Kind=="Video",:);
            testCase.writeText(files.Path,"This is deliberately not an MP4 file.");
            stat = dir(files.Path);
            files.ExpectedBytes = stat.bytes;
            report = hodor.internal.validateFiles(files,ds.sequences,"deep");
            testCase.verifyEqual(report.Status,"FAIL");
            testCase.verifyTrue(contains(report.Message,"Video decode failed"));
        end
    end

    methods (Access=private)
        function writeText(~,path,value)
            folder = fileparts(path);
            if ~isfolder(folder), mkdir(folder); end
            fid = fopen(path,'wt');
            assert(fid>=0,'Could not open test fixture');
            cleaner = onCleanup(@() fclose(fid));
            for line = reshape(string(value),1,[])
                fprintf(fid,'%s\n',line);
            end
        end

        function writeBytes(~,path,n)
            folder = fileparts(path);
            if ~isfolder(folder), mkdir(folder); end
            fid = fopen(path,'wb');
            assert(fid>=0,'Could not open test fixture');
            cleaner = onCleanup(@() fclose(fid));
            fwrite(fid,ones(1,n,'uint8'));
        end

        function replaceFixtureField(testCase,path,original,column,value)
            lines = original;
            fields = split(lines(2),sprintf('\t'));
            fields(column) = value;
            lines(2) = strjoin(fields,sprintf('\t'));
            testCase.writeText(path,lines);
        end

        function writeCountsFixture(testCase)
            columns = ["SeqID","t1","t2","Start","End","c"+string(1:18)];
            row = ["0","1629609208.033","1629609281.673", ...
                "2021-08-22T05:13:28.033","2021-08-22T05:14:41.673",string(1:18)];
            testCase.writeText(fullfile(testCase.Folder,'meta','activity_counts.tsv'), ...
                ["/* synthetic offline counts */";strjoin(columns,sprintf('\t')); ...
                 strjoin(row,sprintf('\t'))]);
        end

        function writeSizeFixtures(testCase)
            header = ["SeqID","c"+string(2:14)];
            row = ["0","1","2","start","end","cam1_0000.mp4","11", ...
                "cam1_0000.txt","12","cam2_0000.mp4","13","cam2_0000.txt","14","0"];
            testCase.writeText(fullfile(testCase.Folder,'meta','camera_metadata.tsv'), ...
                ["/* synthetic offline sizes */";strjoin(header,sprintf('\t')); ...
                 strjoin(row,sprintf('\t'))]);
            header = ["SeqID","t1","t2","start","end","sonar","bytes","ts","tsbytes","frames"];
            row = ["0","1","2","start","end","sonar_0000.mp4","21","sonar_0000.txt","22","0"];
            testCase.writeText(fullfile(testCase.Folder,'meta','sonar_metadata.tsv'), ...
                ["/* synthetic offline sizes */";strjoin(header,sprintf('\t')); ...
                 strjoin(row,sprintf('\t'))]);
        end

        function writeTimestamps(~,path,values)
            folder = fileparts(path);
            if ~isfolder(folder), mkdir(folder); end
            fid = fopen(path,'wt');
            assert(fid>=0,'Could not open timestamp fixture');
            cleaner = onCleanup(@() fclose(fid));
            fprintf(fid,'%.6f\n',values);
        end

        function [files,sequences] = timestampFixture(testCase,offsets)
            ds = hodor.HODORDataset(testCase.Folder,'AllowNetwork',false);
            sequences = ds.sequences;
            files = hodor.internal.fileManifest(testCase.Folder,sequences,0,"sonar",table());
            files = files(files.Kind=="Timestamp",:);
            testCase.writeTimestamps(files.Path,sequences.sequenceStartUnix(1)+offsets);
            stat = dir(files.Path);
            files.ExpectedBytes = stat.bytes;
        end

        function [files,sequences] = videoFixture(testCase,frameCount,brightness,timestampCount)
            profiles = VideoWriter.getProfiles();
            testCase.assumeTrue(any(strcmp({profiles.Name},'MPEG-4')), ...
                'Local MATLAB platform has no MPEG-4 VideoWriter profile.');
            ds = hodor.HODORDataset(testCase.Folder,'AllowNetwork',false);
            sequences = ds.sequences;
            files = hodor.internal.fileManifest(testCase.Folder,sequences,0,"sonar",table());
            mkdir(fileparts(files.Path(1)));
            writer = VideoWriter(files.Path(1),'MPEG-4');
            writer.FrameRate = 10;
            open(writer);
            try
                % Windows MPEG-4 encoders can reject very small frames.
                frame = repmat(uint8(brightness),[128,128,3]);
                for k = 1:frameCount
                    writeVideo(writer,frame);
                end
                close(writer);
            catch ME
                close(writer);
                rethrow(ME)
            end
            testCase.writeTimestamps(files.Path(2), ...
                sequences.sequenceStartUnix(1)+(0:timestampCount-1)/10);
            for k = 1:height(files)
                stat = dir(files.Path(k));
                files.ExpectedBytes(k) = stat.bytes;
            end
        end
    end
end
