classdef TestDownloadQueue < matlab.unittest.TestCase
    % Offline scheduler regressions; fake transfer outcomes, no real waits.
    properties
        Calls double
        First logical
        Waits double
        Codes cell
        Outcomes cell
        Delays cell
        Counts double
    end
    methods (TestMethodSetup)
        function setup(testCase)
            testCase.Calls = [];
            testCase.First = false(1,0);
            testCase.Waits = [];
            testCase.Counts = zeros(1,4);
            testCase.addTeardown(@warning,warning);
            warning('off','hodor:DownloadRetryBlock');
            warning('off','hodor:DownloadFailed');
        end
    end
    methods (Test)
        function allFilesBeforeRetryAndNoRepeatSuccess(testCase)
            testCase.Codes = {[503 200],200,[503 503 200]};
            testCase.Outcomes = {["FAILED","DOWNLOADED"],"SKIPPED",["FAILED","FAILED","DOWNLOADED"]};
            testCase.Delays = {0,0,0};
            [s,~,a] = testCase.runQueue(3,5,10,1);
            testCase.verifyEqual(testCase.Calls,[1 2 3 1 3 3]);
            testCase.verifyEqual(testCase.First,[true true true false false false]);
            testCase.verifyEqual(testCase.Waits,[1 1]);
            testCase.verifyEqual(s,["DOWNLOADED";"SKIPPED";"DOWNLOADED"]);
            testCase.verifyEqual(a,[2;1;3]);
        end
        function fiveBlocksOfTen(testCase)
            testCase.Codes = {503,404};
            testCase.Outcomes = {"FAILED","FAILED"};
            testCase.Delays = {0,0};
            [s,m,a] = testCase.runQueue(2,5,10,1);
            testCase.verifyEqual(a,[51;1]);
            testCase.verifyEqual(s,["FAILED";"FAILED"]);
            testCase.verifyEqual(m,["HTTP 503";"HTTP 404"]);
            testCase.verifyEqual(numel(testCase.Waits),50);
            testCase.verifyEqual(testCase.Calls(1:3),[1 2 1]);
        end
        function serverRetryAfterIsRespected(testCase)
            testCase.Codes = {[429 200],[503 200]};
            testCase.Outcomes = {["FAILED","DOWNLOADED"],["FAILED","DOWNLOADED"]};
            testCase.Delays = {[7 0],[3 0]};
            [s,~,a] = testCase.runQueue(2,1,1,1);
            testCase.verifyEqual(testCase.Waits,7);
            testCase.verifyEqual(s,repmat("DOWNLOADED",2,1));
            testCase.verifyEqual(a,[2;2]);
        end
        function retriesDisabled(testCase)
            testCase.Codes = {503};
            testCase.Outcomes = {"FAILED"};
            testCase.Delays = {0};
            [s,~,a] = testCase.runQueue(1,0,10,1);
            testCase.verifyEqual(s,"FAILED");
            testCase.verifyEqual(a,1);
            testCase.verifyEmpty(testCase.Waits);
        end
        function subRetriesDisabled(testCase)
            testCase.Codes = {503};
            testCase.Outcomes = {"FAILED"};
            testCase.Delays = {0};
            [~,~,a] = testCase.runQueue(1,5,0,1);
            testCase.verifyEqual(a,1);
            testCase.verifyEmpty(testCase.Waits);
        end
        function transientTransportErrorsRetried(testCase)
            testCase.Codes = {[NaN 206],401};
            testCase.Outcomes = {["FAILED","DOWNLOADED"],"FAILED"};
            testCase.Delays = {0,0};
            [s,~,a] = testCase.runQueue(2,2,2,0);
            testCase.verifyEqual(s,["DOWNLOADED";"FAILED"]);
            testCase.verifyEqual(a,[2;1]);
        end
        function noWarningBeforeBlockExhausted(testCase)
            testCase.Codes = {[503 503 200]};
            testCase.Outcomes = {["FAILED","FAILED","DOWNLOADED"]};
            testCase.Delays = {0};
            warning('on','hodor:DownloadRetryBlock');
            warning('on','hodor:DownloadFailed');
            testCase.verifyWarningFree(@()testCase.runQueue(1,5,10,0));
        end
        function warningAtBlockBoundary(testCase)
            testCase.Codes = {503};
            testCase.Outcomes = {"FAILED"};
            testCase.Delays = {0};
            warning('on','hodor:DownloadRetryBlock');
            testCase.verifyWarning(@()testCase.runQueue(1,1,2,0),'hodor:DownloadRetryBlock');
            testCase.verifyEqual(testCase.Counts(1),3);
        end
    end
    methods (Access=private)
        function [s,m,a] = runQueue(testCase,n,retries,subRetries,delay)
            [s,m,a] = hodor.internal.downloadQueue(n, ...
                @(k,first)testCase.fakeAttempt(k,first), ...
                'Retries',retries,'SubRetries',subRetries,'RetryDelay',delay, ...
                'Wait',@(seconds)testCase.fakeWait(seconds));
        end
        function [s,m,c,d] = fakeAttempt(testCase,k,first)
            testCase.Calls(end+1) = k;
            testCase.First(end+1) = first;
            testCase.Counts(k) = testCase.Counts(k)+1;
            i = testCase.Counts(k);
            c = testCase.Codes{k}(min(i,numel(testCase.Codes{k})));
            s = testCase.Outcomes{k}(min(i,numel(testCase.Outcomes{k})));
            d = testCase.Delays{k}(min(i,numel(testCase.Delays{k})));
            m = "HTTP "+string(c);
        end
        function fakeWait(testCase,seconds)
            testCase.Waits(end+1) = seconds;
        end
    end
end
