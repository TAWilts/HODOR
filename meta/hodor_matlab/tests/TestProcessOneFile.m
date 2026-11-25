classdef TestProcessOneFile < matlab.unittest.TestCase
    properties
        Root string
        Scratch string
        Results string
        File table
    end
    methods (TestMethodSetup)
        function setup(testCase)
            testCase.Root = string(tempname);
            mkdir(testCase.Root);
            testCase.addTeardown(@()rmdir(testCase.Root,'s'));
            testCase.Scratch = fullfile(testCase.Root,'scratch');
            testCase.Results = fullfile(testCase.Root,'results');
            mkdir(testCase.Scratch);
            mkdir(testCase.Results);
            testCase.File = table(0,"sonar","Timestamp","sonar/sonar_0000.txt", ...
                "unused","https://invalid.invalid/unused",3, ...
                'VariableNames',{'SeqID','Sensor','Kind','RelativePath','Path','URL','ExpectedBytes'});
        end
    end
    methods (Test)
        function successSavesThenDeletes(testCase)
            [s,~,out,raw] = testCase.invokeOne(@(f)fileread(f.Path),@TestProcessOneFile.downloadOK);
            testCase.verifyEqual(s,"PROCESSED");
            testCase.verifyEqual(raw,"");
            testCase.verifyTrue(isfile(out));
            testCase.verifyFalse(isfile(fullfile(testCase.Scratch,'sonar_0000.txt')));
            saved = load(out,'result','source');
            testCase.verifyEqual(saved.result,'abc');
            testCase.verifyEqual(saved.source.RelativePath,testCase.File.RelativePath);
        end
        function failurePreservesRaw(testCase)
            [s,~,out,raw] = testCase.invokeOne(@TestProcessOneFile.failProcessor,@TestProcessOneFile.downloadOK);
            testCase.verifyEqual(s,"FAILED");
            testCase.verifyTrue(isfile(raw));
            testCase.verifyFalse(isfile(out));
        end
        function restartSkipsSavedResult(testCase)
            [s,~,out] = testCase.invokeOne(@(f)fileread(f.Path),@TestProcessOneFile.downloadOK);
            testCase.assertEqual(s,"PROCESSED");
            before = fileread(fullfile(testCase.Root,'sentinel.txt'));
            [s,~,same] = testCase.invokeOne(@TestProcessOneFile.failProcessor,@TestProcessOneFile.failDownload);
            testCase.verifyEqual(s,"SKIPPED");
            testCase.verifyEqual(same,out);
            testCase.verifyEqual(fileread(fullfile(testCase.Root,'sentinel.txt')),before);
        end
        function failedDownloadPreservesPartial(testCase)
            [s,~,out,raw] = testCase.invokeOne(@TestProcessOneFile.failProcessor,@TestProcessOneFile.partialDownload);
            testCase.verifyEqual(s,"FAILED");
            testCase.verifyTrue(isfile(raw+".part"));
            testCase.verifyFalse(isfile(out));
        end
        function preexistingScratchIsNotDeleted(testCase)
            p = fullfile(testCase.Scratch,'sonar_0000.txt');
            TestProcessOneFile.writeText(p,'original');
            [s,~,out] = testCase.invokeOne(@TestProcessOneFile.failProcessor,@TestProcessOneFile.failDownload);
            testCase.verifyEqual(s,"FAILED");
            testCase.verifyEqual(fileread(p),'original');
            testCase.verifyFalse(isfile(out));
        end
    end
    methods (Access=private)
        function [s,m,o,r] = invokeOne(testCase,processor,download)
            TestProcessOneFile.writeText(fullfile(testCase.Root,'sentinel.txt'),'untouched');
            [s,m,o,r] = hodor.internal.processOneFile(testCase.File,testCase.Scratch, ...
                testCase.Results,processor,download);
        end
    end
    methods (Static)
        function [s,m] = downloadOK(file)
            TestProcessOneFile.writeText(file.Path,'abc');
            s = "DOWNLOADED"; m = "OK";
        end
        function [s,m] = partialDownload(file)
            TestProcessOneFile.writeText(file.Path+".part",'a');
            s = "FAILED"; m = "HTTP 503";
        end
        function [s,m] = failDownload(~)
            error('hodor:TestUnexpectedDownload','Downloader should not be called.');
        end
        function result = failProcessor(~)
            error('hodor:TestProcessor','Simulated processing failure.');
        end
        function writeText(p,t)
            fid = fopen(p,'wb');
            assert(fid>=0);
            c = onCleanup(@()fclose(fid)); %#ok<NASGU>
            fwrite(fid,uint8(t),'uint8');
        end
    end
end
