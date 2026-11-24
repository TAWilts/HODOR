classdef TestChecksums < matlab.unittest.TestCase
    % Offline SHA-256 regressions; no PANGAEA requests or video codec.
    properties
        Root string
    end
    methods (TestMethodSetup)
        function fixture(testCase)
            testCase.Root = string(tempname)+" HODOR checksums";
            mkdir(fullfile(testCase.Root,'meta'));
            suiteFolder = fileparts(fileparts(mfilename('fullpath')));
            lines = readlines(fullfile(fileparts(suiteFolder),'sequences.csv'));
            writelines(lines(1:3),fullfile(testCase.Root,'meta','sequences.csv'));
            mkdir(fullfile(testCase.Root,'sonar'));
        end
    end
    methods (TestMethodTeardown)
        function cleanup(testCase)
            if isfolder(testCase.Root), rmdir(testCase.Root,'s'); end
        end
    end
    methods (Test)
        function standardHashVector(testCase)
            p = testCase.mediaPath();
            testCase.writeBinary(p,uint8('abc'));
            [hash,bytes] = hodor.internal.sha256File(p);
            testCase.verifyEqual(hash,"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
            testCase.verifyEqual(bytes,3);
        end
        function multiblockBinaryHash(testCase)
            p = testCase.mediaPath();
            testCase.writeBinary(p,repmat(uint8(0:255),1,8193));
            [hash,bytes] = hodor.internal.sha256File(p);
            testCase.verifyEqual(hash,"ad4707187ce2c9c3d16909bd20eb1c440fa9d2717bff5b836db2d32f997da4d2");
            testCase.verifyEqual(bytes,2097408);
        end
        function emptyHashVector(testCase)
            p = testCase.mediaPath();
            testCase.writeBinary(p,uint8([]));
            [hash,bytes] = hodor.internal.sha256File(p);
            testCase.verifyEqual(hash,"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
            testCase.verifyEqual(bytes,0);
        end
        function specialFilenameAndEnvironmentRestoration(testCase)
            p = fullfile(testCase.Root,"a & b's 100% (test).bin");
            testCase.writeBinary(p,uint8('abc'));
            name = 'HODOR_SHA256_FILE';
            previous = getenv(name);
            restore = onCleanup(@()setenv(name,previous)); %#ok<NASGU>
            setenv(name,'original sentinel value');
            [hash,bytes] = hodor.internal.sha256File(p);
            testCase.verifyEqual(hash,"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
            testCase.verifyEqual(bytes,3);
            testCase.verifyEqual(getenv(name),'original sentinel value');
        end
        function recordAndVerify(testCase)
            ds = testCase.dataset();
            testCase.writeBinary(testCase.mediaPath(),uint8([97 98 99 0 255]));
            report = ds.recordChecksums(0,'Sensors','sonar');
            testCase.verifyEqual(report.Status,["RECORDED";"MISSING"]);
            testCase.verifyEqual(report.ActualSHA256(1),"77cb6bea091ff250af304a09024b0c526be6a21014a91ab56e788c63a69e811f");
            testCase.verifyEqual(report.Origin(1),"local");
            testCase.verifyTrue(isfile(testCase.baselinePath()));
            testCase.verifyTrue(isfile(fullfile(testCase.Root,'reports','checksum_record.csv')));
            baseline = fileread(testCase.baselinePath());
            reopened = testCase.dataset();
            checked = reopened.verifyChecksums(0,'Sensors','sonar');
            testCase.verifyEqual(checked.Status,["MATCH";"MISSING"]);
            testCase.verifyEqual(fileread(testCase.baselinePath()),baseline);
            testCase.verifyTrue(isfile(fullfile(testCase.Root,'reports','checksum_verify.csv')));
        end
        function equalSizeCorruptionAndNoOverwrite(testCase)
            ds = testCase.dataset();
            p = testCase.mediaPath();
            testCase.writeBinary(p,uint8('abc'));
            ds.recordChecksums(0,'Sensors','sonar');
            baseline = fileread(testCase.baselinePath());
            testCase.writeBinary(p,uint8('xbc'));
            r = ds.verifyChecksums(0,'Sensors','sonar');
            testCase.verifyEqual(r.Status(1),"MISMATCH");
            testCase.verifyEqual(r.ReferenceBytes(1),r.Bytes(1));
            r = ds.recordChecksums(0,'Sensors','sonar');
            testCase.verifyEqual(r.Status(1),"MISMATCH");
            testCase.verifyEqual(fileread(testCase.baselinePath()),baseline);
            testCase.verifyEqual(fileread(p),'xbc');
        end
        function unknownEmptyMissingDoNotCreateBaseline(testCase)
            ds = testCase.dataset();
            testCase.writeBinary(testCase.mediaPath(),uint8('abc'));
            testCase.writeBinary(fullfile(testCase.Root,'sonar','sonar_0000.txt'),uint8([]));
            r = ds.verifyChecksums(0,'Sensors','sonar','SaveReport',false);
            testCase.verifyEqual(r.Status,["NO_BASELINE";"EMPTY"]);
            testCase.verifyFalse(isfile(testCase.baselinePath()));
            r = ds.recordChecksums(1,'Sensors','sonar');
            testCase.verifyEqual(r.Status,["MISSING";"MISSING"]);
            testCase.verifyFalse(isfile(testCase.baselinePath()));
        end
        function portableRelativePaths(testCase)
            ds = testCase.dataset();
            testCase.writeBinary(testCase.mediaPath(),uint8('abc'));
            ds.recordChecksums(0,'Sensors','sonar');
            moved = fullfile(testCase.Root,'copied dataset');
            mkdir(moved);
            copyfile(fullfile(testCase.Root,'meta'),fullfile(moved,'meta'));
            copyfile(fullfile(testCase.Root,'sonar'),fullfile(moved,'sonar'));
            ds2 = hodor.HODORDataset(moved,'AllowNetwork',false);
            r = ds2.verifyChecksums(0,'Sensors','sonar');
            testCase.verifyEqual(r.Status(1),"MATCH");
            testCase.verifyEqual(r.RelativePath(1),"sonar/sonar_0000.mp4");
        end
        function malformedBaselineFailsClosed(testCase)
            ds = testCase.dataset();
            testCase.writeBinary(testCase.mediaPath(),uint8('abc'));
            ds.recordChecksums(0,'Sensors','sonar');
            p = testCase.baselinePath();
            lines = readlines(p);
            lines = lines(strlength(lines)>0);
            writelines([lines;lines(end)],p);
            invalid = fileread(p);
            testCase.verifyError(@()ds.recordChecksums(0,'Sensors','sonar'), ...
                'hodor:ChecksumManifest');
            testCase.verifyEqual(fileread(p),invalid);
        end
        function optionalValidationReportsMismatch(testCase)
            ds = testCase.dataset();
            testCase.writeBinary(testCase.mediaPath(),uint8('abc'));
            ds.recordChecksums(0,'Sensors','sonar');
            testCase.writeBinary(testCase.mediaPath(),uint8('xbc'));
            plain = ds.validateSequence(0,'Sensors','sonar','Level','quick');
            testCase.verifyFalse(ismember('ChecksumStatus',plain.Properties.VariableNames));
            checked = ds.validateSequence(0,'Sensors','sonar','Level','quick','CheckSHA256',true);
            testCase.verifyEqual(checked.ChecksumStatus(1),"MISMATCH");
            testCase.verifyEqual(checked.Status(1),"FAIL");
        end
        function downloadOriginPreserved(testCase)
            ds = testCase.dataset();
            testCase.writeBinary(testCase.mediaPath(),uint8('abc'));
            files = hodor.internal.fileManifest(testCase.Root,ds.sequences,0,"sonar",table());
            r = hodor.internal.checksumFiles(testCase.Root,files(1,:),"record","download");
            testCase.verifyEqual(r.Status,"RECORDED");
            testCase.verifyEqual(r.Origin,"download");
            r = ds.recordChecksums(0,'Sensors','sonar');
            testCase.verifyEqual(r.Status(1),"MATCH");
            testCase.verifyEqual(r.Origin(1),"download");
        end
    end
    methods (Access=private)
        function ds = dataset(testCase)
            ds = hodor.HODORDataset(testCase.Root,'AllowNetwork',false);
        end
        function p = mediaPath(testCase)
            p = fullfile(testCase.Root,'sonar','sonar_0000.mp4');
        end
        function p = baselinePath(testCase)
            p = fullfile(testCase.Root,'meta','checksums_sha256.tsv');
        end
        function writeBinary(~,p,bytes)
            fid = fopen(p,'wb');
            assert(fid>=0,'Cannot create fixture');
            cleaner = onCleanup(@()fclose(fid)); %#ok<NASGU>
            assert(fwrite(fid,bytes,'uint8')==numel(bytes),'Fixture write failed');
        end
    end
end
