classdef TestHODOR < matlab.unittest.TestCase
    % Offline regression tests. No PANGAEA requests and no video codec needed.
    properties
        Folder string
    end
    methods (TestMethodSetup)
        function createFixture(testCase)
            testCase.Folder = string(tempname);
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
    end
end
