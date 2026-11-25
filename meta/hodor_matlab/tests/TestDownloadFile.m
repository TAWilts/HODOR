classdef TestDownloadFile < matlab.unittest.TestCase
    % Exercise the actual downloader without contacting an external server.
    properties
        Root string
    end
    methods (TestMethodSetup)
        function setup(testCase)
            testCase.Root = string(tempname);
            mkdir(testCase.Root);
            testCase.addTeardown(@()rmdir(testCase.Root,'s'));
        end
    end
    methods (Test)
        function existingFileIsSkipped(testCase)
            p = fullfile(testCase.Root,'existing.txt');
            testCase.writeBytes(p,uint8('abc'));
            [s,m,code,delay] = hodor.internal.downloadFile( ...
                "https://invalid.invalid/unused",p,3,'Retries',0);
            testCase.verifyEqual(s,"SKIPPED");
            testCase.verifyTrue(contains(m,"published byte size"));
            testCase.verifyTrue(isnan(code));
            testCase.verifyEqual(delay,0);
            testCase.verifyEqual(fileread(p),'abc');
        end
        function completePartialIsPromoted(testCase)
            p = fullfile(testCase.Root,'complete.txt');
            testCase.writeBytes(p+".part",uint8('abc'));
            [s,m,code,delay] = hodor.internal.downloadFile( ...
                "https://invalid.invalid/unused",p,3,'Retries',0);
            testCase.verifyEqual(s,"DOWNLOADED");
            testCase.verifyTrue(contains(m,"pre-existing partial"));
            testCase.verifyTrue(isnan(code));
            testCase.verifyEqual(delay,0);
            testCase.verifyEqual(fileread(p),'abc');
            testCase.verifyFalse(isfile(p+".part"));
        end
        function forcedRetryPreservesCompletedPartial(testCase)
            p = fullfile(testCase.Root,'forced.txt');
            testCase.writeBytes(p,uint8('old'));
            testCase.writeBytes(p+".part",uint8('new'));
            [s,~,~,~] = hodor.internal.downloadFile( ...
                "https://invalid.invalid/unused",p,3,'Retries',0, ...
                'Force',true,'ResetPartial',false);
            testCase.verifyEqual(s,"DOWNLOADED");
            testCase.verifyEqual(fileread(p),'new');
            testCase.verifyFalse(isfile(p+".part"));
        end
    end
    methods (Access=private)
        function writeBytes(~,filename,bytes)
            fid = fopen(filename,'wb');
            assert(fid>=0,'Cannot open test fixture.');
            closer = onCleanup(@()fclose(fid)); %#ok<NASGU>
            assert(fwrite(fid,bytes,'uint8')==numel(bytes),'Fixture write failed.');
        end
    end
end
