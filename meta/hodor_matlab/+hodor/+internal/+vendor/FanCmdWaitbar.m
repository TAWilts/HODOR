classdef FanCmdWaitbar < handle
    % FanCmdWaitbar
    % Simple and fancy tqdm-like command-line progress bar for MATLAB.
    %
    % FanCmdWaitbar supports classical sequential progress bars, parfor-safe
    % updates through a DataQueue, and vector-style progress for non-sequential
    % workloads.
    %
    % Example 1: automatic increment
    %   wb = FanCmdWaitbar(100);
    %   for k = 1:100
    %       pause(0.05)
    %       wb.step();
    %   end
    %
    % Example 2: explicit index
    %   wb = FanCmdWaitbar(200, 'startIdx', 1, 'title', 'Training');
    %   for k = 1:200
    %       pause(0.02)
    %       wb.step(k, sprintf('epoch item %d', k));
    %   end
    %
    % Example 3: nested waitbars
    %   wb = FanCmdWaitbar(200, 'startIdx', 1, 'title', 'Training');
    %   for k = 1:200
    %       wb.step(k, sprintf('epoch item %d', k));
    %       wb2 = FanCmdWaitbar(10, 'title', 'Batch');
    %       for b = 1:10
    %           pause(0.2)
    %           wb2.step()
    %       end
    %       wb2.clc()
    %   end
    %
    % Example 4: parfor
    %   N = 100;
    %   wb = FanCmdWaitbar(N, 'title', 'Send the minions', 'mode', 'parfor');
    %   parfor k = 1:N
    %       pause(randi(20) * 0.1)
    %       wb.step([], sprintf('minion %d', k))
    %   end
    %
    % Example 5: vector-style progress for non-sequential work
    %   wb = FanCmdWaitbar(5, 'barStyle', 'vector', 'showTime', false);
    %   wb.step(1)              % marks item 1 as done
    %   wb.step(3)              % marks item 3 as done
    %   wb.step(4, '', 'x')     % marks item 4 with custom symbol x
    %
    % Example 6: vector-style parfor progress
    %   N = 100;
    %   wb = FanCmdWaitbar(N, 'mode', 'parfor', 'barStyle', 'vector');
    %   parfor k = 1:N
    %       pause(rand)
    %       wb.step(k, sprintf('item %d', k))
    %   end
    %
    % Example 7: vector-style state display
    %   N = 100;
    %   wb = FanCmdWaitbar(N, ...
    %       'title', 'Converting Images', ...
    %       'barStyle', 'vector', ...
    %       'vectorDoneChar', 'S');
    %
    %   for k = randperm(N)
    %       wb.step(k, [], 'L')                         % loading
    %       wb.step(k, [], 'P')                         % processing
    %       wb.step(k, sprintf('img %d saved', k), 'S') % saved / finished
    %   end
    %
    % Example 8: vector-style parfor with states
    %   N = 100;
    %   wb = FanCmdWaitbar(N, ...
    %       'title', 'Converting Images', ...
    %       'mode', 'parfor', ...
    %       'barStyle', 'vector', ...
    %       'vectorDoneChar', 'S');
    %
    %   parfor k = 1:N
    %       wb.step(k, [], 'L')
    %       wb.step(k, [], 'P')
    %       wb.step(k, sprintf('img %d processed', k), 'S')
    %   end
    %
    % Example 9: status update without advancing progress
    %   wb = FanCmdWaitbar(100, 'title', 'Training');
    %   for k = 1:100
    %       wb.step(k, sprintf('epoch %d: loading batch', k));
    %       pause(0.05)
    %
    %       wb.step("status", sprintf('epoch %d: processing batch', k));
    %       pause(0.05)
    %
    %       wb.step("s", sprintf('epoch %d: saving results', k));
    %       pause(0.05)
    %   end
    %
    % Constructor:
    %   wb = FanCmdWaitbar(endIdx, Name, Value)
    %
    % Required:
    %   endIdx              Final iteration index.
    %
    % Optional parameters:
    %   startIdx            Start index. Default: 1.
    %   showTime            Show elapsed, remaining, and estimated total time.
    %                       Default: true.
    %   title               Optional title shown before the bar. Default: ''.
    %   mode                Execution mode: 'default' or 'parfor'.
    %                       Default: 'default'.
    %   barStyle            Display style: 'bar' or 'vector'.
    %                       Default: 'bar'.
    %   vectorEmptyChar     Character for empty vector entries. Default: '-'.
    %   vectorDoneChar      Character that represents a completed vector entry.
    %                       Default: 'o'.
    %   vectorPartialChar   Character for grouped mixed states when
    %                       vectorDoneChar is the default 'o'. Default: '+'.
    %
    % step(): update progress
    %   wb.step()
    %   wb.step(i)
    %   wb.step(i, currentTopic)
    %   wb.step(i, currentTopic, symbol)
    %   wb.step([], currentTopic)
    %   wb.step([], currentTopic, symbol)
    %   wb.step("s", currentTopic)
    %   wb.step("status", currentTopic)
    %
    % The special index commands "s" and "status" update only the displayed
    % topic/status message. They do not advance the progress index and are
    % excluded from time estimation. This is useful for reporting intermediate
    % states without affecting the progress or remaining-time estimate.
    %
    % In bar style:
    %   - Progress is based on the current index or auto-incremented steps.
    %   - In parfor mode, pass [] as the index because iterations finish out of
    %     order.
    %
    % In vector style:
    %   - Progress is based on marked indices, not on the largest index.
    %   - This is useful for non-sequential workloads such as parfor.
    %   - The optional symbol argument sets the visible state of the given item.
    %   - Only entries equal to vectorDoneChar count as completed.
    %   - With the default vectorDoneChar='o', mixed compressed groups use
    %     vectorPartialChar.
    %   - With a custom vectorDoneChar, mixed compressed groups show the least
    %     frequent state in that group, which often indicates what the group is
    %     currently waiting on.
    %
    % clc():
    %   Clears the last rendered progress line.
    %
    % Notes:
    %   - Uses a single command-window line and overwrites it.
    %   - Additional fprintf/disp/warning output may interfere with rendering.
    %   - parfor mode keeps the waitbar on the client and sends updates through
    %     parallel.pool.DataQueue.
    %
    % Checkout the [Matlab File Exchange](https://de.mathworks.com/matlabcentral/fileexchange/183723-fancmdwaitbar)
    % or [GitHub](https://github.com/tawilts/FanCmdWaitbar) for more information and updates.
    %
    % Author: T. A. Wilts
    % License: MIT

    properties (Access = private)
        startIdx (1,1) double = 1
        endIdx   (1,1) double

        showTime (1,1) logical = true
        title    (1,:) char = ''

        mode    (1,:) char = 'default'
        loopModes (1,:) string = ["default","parfor"]

        barStyle (1,:) char = 'bar'
        barStyles (1,:) string = ["bar","vector"]

        % for vector-style progress
        vectorState (1,:) string
        vectorEmptyChar   (1,:) char = '-'
        vectorDoneChar    (1,:) char = 'o'
        vectorPartialChar (1,:) char = '+'

        % for parfor
        parforQueue

        lastTopic char = ''

        currentIdx (1,1) double
        startTime datetime

        lastElapsedSeconds (1,1) double = 0

        lastPrintLength (1,1) double = 0
        finished (1,1) logical = false
        clearAfterFinish (1,1) logical = false

        barFillChar  (1,:) char = '='
        barHeadChar  (1,:) char = '>'
        barEmptyChar (1,:) char = ' '
    end
    properties (Access = private, Transient)
        parforListener = []
    end

    methods
        function obj = FanCmdWaitbar(endIdx, varargin)
            % Constructor with name-value arguments

            p = inputParser;
            addParameter(p, 'startIdx', 1, @(x) isnumeric(x) && isscalar(x));
            addParameter(p, 'showTime', true, @(x) islogical(x) || isnumeric(x));
            addParameter(p, 'title', '', @(x) ischar(x) || isstring(x));
            addParameter(p, 'mode', 'default', @(x) ischar(x) || isstring(x));
            addParameter(p, 'barStyle', 'bar', @(x) ischar(x) || isstring(x));
            addParameter(p, 'vectorEmptyChar', '-', @(x) ischar(x) || isstring(x));
            addParameter(p, 'vectorDoneChar', 'o', @(x) ischar(x) || isstring(x));
            addParameter(p, 'vectorPartialChar', '+', @(x) ischar(x) || isstring(x));
            parse(p, varargin{:});

            if isempty(endIdx)
                error('FanCmdWaitbar:MissingEndIdx', ...
                    'You must provide ''endIdx''.');
            end

            obj.startIdx = p.Results.startIdx;
            obj.endIdx   = endIdx;
            obj.showTime = logical(p.Results.showTime);
            obj.title    = char(string(p.Results.title));
            obj.mode     = lower(char(string(p.Results.mode)));
            obj.barStyle = lower(char(string(p.Results.barStyle)));

            if ~any(strcmp(obj.mode, obj.loopModes))
                error('FanCmdWaitbar:InvalidMode', ...
                    sprintf('%s is not a valid mode. Choose one of: %s', ...
                    obj.mode, strjoin(obj.loopModes, ', ')))
            end

            if ~any(strcmp(obj.barStyle, obj.barStyles))
                error('FanCmdWaitbar:InvalidBarStyle', ...
                    sprintf('%s is not a valid barStyle. Choose one of: %s', ...
                    obj.barStyle, strjoin(obj.barStyles, ', ')))
            end

            if obj.endIdx < obj.startIdx
                error('FanCmdWaitbar:InvalidRange', ...
                    '''endIdx'' must be >= ''startIdx''.');
            end

            obj.vectorEmptyChar   = obj.firstChar(p.Results.vectorEmptyChar);
            obj.vectorDoneChar    = obj.firstChar(p.Results.vectorDoneChar);
            obj.vectorPartialChar = obj.firstChar(p.Results.vectorPartialChar);

            totalSteps = obj.endIdx - obj.startIdx + 1;
            obj.vectorState = strings(1, totalSteps);
            obj.vectorState(:) = "";

            % In parfor, setup queue. The waitbar is rendered on the client;
            % workers only send compact progress events through the queue.
            if strcmp(obj.mode, 'parfor')
                obj.parforQueue = parallel.pool.DataQueue;
                obj.parforListener = afterEach(obj.parforQueue, ...
                    @(data) obj.internalStep(data.i, data.currentTopic, data.symbol));
            end

            obj.currentIdx = obj.startIdx - 1;
            obj.startTime  = datetime('now');

            obj.render('');
        end

        function step(obj, i, currentTopic, symbol)
            % step()                         -> auto increment by 1
            % step(i)                        -> set current progress
            % step(i, currentTopic)          -> set progress + topic
            % step(i, currentTopic, symbol)  -> set progress + topic + symbol
            % step([], currentTopic)         -> auto increment + topic
            %
            % In parfor-mode, this same method sends a progress event to the
            % client-side DataQueue instead of rendering directly.

            if nargin < 4
                symbol = '';
            end
            if nargin < 3
                currentTopic = '';
            end
            if nargin < 2
                i = [];
            end

            switch obj.mode
                case 'default'
                    obj.internalStep(i, currentTopic, symbol)

                case 'parfor'
                    % For normal bar style, i is usually intentionally empty,
                    % because parfor iterations finish out of order. For vector
                    % style, passing i is expected and useful.
                    if ~isempty(i) && strcmp(obj.barStyle, 'bar')
                        warning('FanCmdWaitbar:stepInParfor', ...
                            ['In parfor-mode with barStyle="bar", ''i'' should usually be empty: ', ...
                            'FanCmdWaitbar.step([], ...). Use barStyle="vector" for indexed progress.'])
                    end

                    data = struct();
                    data.i = i;
                    data.currentTopic = currentTopic;
                    data.symbol = symbol;
                    send(obj.parforQueue, data);
            end
        end

        function delete(obj)
            if ~isempty(obj.parforListener)
                delete(obj.parforListener);
            end

            % if ~obj.finished && obj.lastPrintLength > 0
            %     fprintf('\n');
            % end
        end

        function clc(obj)
            fprintf(repmat('\b', 1, obj.lastPrintLength));
            obj.lastPrintLength = 0;
        end
    end

    methods (Access = private)
        function internalStep(obj, i, currentTopic, symbol)


            if nargin < 4 || isempty(symbol)
                symbol = obj.vectorDoneChar;
            else
                symbol = obj.firstChar(symbol);
            end

            excludeFromTimeEstimation = false;

            if nargin < 2
                i = [];
            end
            isStatusUpdate = false;

            if (isstring(i) || ischar(i))
                if strcmpi(i,"s") || strcmpi(i,"status")
                    i = obj.currentIdx;
                    isStatusUpdate = true;
                else
                    error('FanCmdWaitbar:InvalidStepCommand', ...
                    '''i'' must be numeric or ''s'' or ''status''.')
                end
            end

            if obj.finished && ~isStatusUpdate
                return
            end

            if isempty(i)
                obj.currentIdx = obj.currentIdx + 1;
            else
    
                validateattributes(i, {'numeric'}, {'scalar','finite'});

                % Check if new idx is above current idx for time estimation.
                % In vector style, out-of-order indices are expected, so this
                % only prevents the estimate from jumping backwards.
                if obj.currentIdx >= i || isStatusUpdate
                    excludeFromTimeEstimation = true;
                end

                obj.currentIdx = i;
            end

            if nargin < 3 || isempty(currentTopic)
                currentTopic = '';
            else
                currentTopic = char(string(currentTopic));
            end

            if obj.currentIdx < obj.startIdx && ~isStatusUpdate
                obj.currentIdx = obj.startIdx;
            end

            if obj.currentIdx > obj.endIdx
                obj.currentIdx = obj.endIdx;
            end

            if strcmp(obj.barStyle, 'vector')
                obj.updateVectorState(obj.currentIdx, symbol);
            end

            if obj.isComplete()
                obj.render(currentTopic, excludeFromTimeEstimation);
                obj.finished = true;
            else
                obj.render(currentTopic, excludeFromTimeEstimation);
            end
        end

        function render(obj, currentTopic, excludeFromTimeEstimation)
            arguments
                obj
                currentTopic = ''
                excludeFromTimeEstimation = false
            end

            if isempty(currentTopic)
                currentTopic = obj.lastTopic;
            end

            % If the new index did not increase, omit time estimation.
            if excludeFromTimeEstimation
                elapsedSeconds = obj.lastElapsedSeconds;
            else
                elapsedSeconds = seconds(datetime('now') - obj.startTime);
                obj.lastElapsedSeconds = elapsedSeconds;
            end

            totalSteps = obj.endIdx - obj.startIdx + 1;

            switch obj.barStyle
                case 'vector'
                    doneSteps = nnz(obj.vectorState == obj.vectorDoneChar);
                otherwise
                    doneSteps = max(0, obj.currentIdx - obj.startIdx + 1);
            end

            doneSteps = min(doneSteps, totalSteps);

            if totalSteps <= 0
                frac = 1;
            else
                frac = doneSteps / totalSteps;
            end

            percent = 100 * frac;
            idxStr = sprintf(' %d/%d', doneSteps, totalSteps);

            if obj.showTime && doneSteps > 0
                estTotal = elapsedSeconds / doneSteps * totalSteps;
                remaining = max(estTotal - elapsedSeconds, 0);

                timeStr = sprintf(' %s<%s, Total~%s', ...
                    obj.formatTime(elapsedSeconds), ...
                    obj.formatTime(remaining), ...
                    obj.formatTime(estTotal));
            elseif obj.showTime
                timeStr = sprintf(' %s<%s, Total~%s', ...
                    obj.formatTime(0), ...
                    '--:--:--', ...
                    '--:--:--');
            else
                timeStr = '';
            end

            titleStr = strtrim(obj.title);
            if ~isempty(titleStr)
                titleStr = [titleStr ' | '];
            end

            suffixParts = [char(sprintf('%6.2f%%%%', percent)), idxStr, timeStr];
            suffix = [suffixParts, ' | '];

            if ~isempty(currentTopic)
                topicPrefix = ' | ';
            else
                topicPrefix = '';
            end

            cmdWidth = obj.getCommandWindowWidth();

            % Reserve at least a minimum bar width.
            minBarWidth = 10;

            % Determine topic width dynamically after bar/suffix placement.
            fixedWithoutBar = length(titleStr) + 2 + length(suffix);
            % 2 for the two '|' around the bar.

            availableForBarAndTopic = cmdWidth - fixedWithoutBar;

            if availableForBarAndTopic < minBarWidth + 1
                barWidth = minBarWidth;
                topicStr = '';
            else
                % Use most of the remaining width for the bar,
                % leave some optional room for the topic.
                if isempty(currentTopic)
                    barWidth = availableForBarAndTopic - 2;
                    topicStr = '';
                else
                    % Keep at least ~25 chars for topic if possible.
                    desiredTopic = min(35, max(10, floor(0.25 * cmdWidth)));
                    barWidth = max(minBarWidth, availableForBarAndTopic - length(topicPrefix) - desiredTopic);
                    maxTopicWidth = max(0, cmdWidth - (fixedWithoutBar + barWidth + length(topicPrefix)));
                    topicStr = obj.truncateText(currentTopic, maxTopicWidth);
                    if isempty(topicStr)
                        topicPrefix = '';
                    else
                        obj.lastTopic = topicStr;
                    end
                end
            end

            switch obj.barStyle
                case 'bar'
                    bar = obj.makeBar(frac, barWidth);
                case 'vector'
                    bar = obj.makeVectorBar(barWidth);
            end

            line = sprintf('%s|%s| %s%s%s', ...
                titleStr, bar, suffix, topicPrefix, topicStr);

            % In case line still became too long, hard-truncate.
            if length(line) > cmdWidth
                line = obj.truncateText(line, cmdWidth);
            end

            % Overwrite previous line completely.
            if obj.lastPrintLength > 0
                obj.clc();
            end

            fprintf('%s\n', line);
            obj.lastPrintLength = length(line) + 1;
        end

        function bar = makeBar(obj, frac, width)
            width = max(1, floor(width));
            filled = floor(frac * width);

            if frac >= 1
                bar = repmat(obj.barFillChar, 1, width);
                return
            end

            if filled <= 0
                bar = [obj.barHeadChar repmat(obj.barEmptyChar, 1, width - 1)];
            elseif filled >= width
                bar = repmat(obj.barFillChar, 1, width);
            else
                bar = [ ...
                    repmat(obj.barFillChar, 1, max(filled - 1, 0)), ...
                    obj.barHeadChar, ...
                    repmat(obj.barEmptyChar, 1, width - filled) ...
                    ];
            end
        end

        function updateVectorState(obj, idx, symbol)
            localIdx = idx - obj.startIdx + 1;

            if localIdx < 1 || localIdx > numel(obj.vectorState)
                return
            end

            obj.vectorState(localIdx) = string(symbol);
        end

        function tf = isComplete(obj)
            switch obj.barStyle
                case 'bar'
                    tf = obj.currentIdx >= obj.endIdx;
                case 'vector'
                    tf = nnz(obj.vectorState == obj.vectorDoneChar) >= numel(obj.vectorState);
                otherwise
                    tf = obj.currentIdx >= obj.endIdx;
            end
        end

        function bar = makeVectorBar(obj, width)
            width = max(1, floor(width));
            nSteps = numel(obj.vectorState);

            if nSteps == 0
                bar = repmat(obj.vectorEmptyChar, 1, width);
                return
            end

            barChars = repmat(obj.vectorEmptyChar, 1, width);

            if nSteps <= width
                % Expansion: each logical step occupies a visible group so
                % that the available bar width is still used.
                edges = round(linspace(1, width + 1, nSteps + 1));

                for s = 1:nSteps
                    b1 = edges(s);
                    b2 = edges(s + 1) - 1;

                    b1 = max(1, min(b1, width));
                    b2 = max(1, min(b2, width));

                    if b2 < b1
                        b2 = b1;
                    end

                    if obj.vectorState(s) ~= ""
                        symbol = char(obj.vectorState(s));
                        barChars(b1:b2) = symbol(1);
                    end
                end
            else
                % Compression: multiple logical steps are represented by one
                % visible character. Empty/partial/full groups are indicated.
                edges = round(linspace(1, nSteps + 1, width + 1));

                for b = 1:width
                    idx1 = edges(b);
                    idx2 = edges(b + 1) - 1;

                    idx1 = max(1, min(idx1, nSteps));
                    idx2 = max(1, min(idx2, nSteps));

                    if idx2 < idx1
                        idx2 = idx1;
                    end

                    group = obj.vectorState(idx1:idx2);
                    isDone = group == obj.vectorDoneChar;

                    if ~any(isDone)
                        barChars(b) = obj.vectorEmptyChar;
                    elseif all(isDone)
                        doneSymbols = group(isDone);
                        symbol = char(doneSymbols(end));
                        barChars(b) = symbol(1);
                    else
                        if obj.vectorDoneChar == 'o'
                            barChars(b) = obj.vectorPartialChar;
                        else
                            catData = categorical(group);
                            % histcounts counts unique categories automatically
                            [counts, categories] = histcounts(catData);
                            [~,i] = min(counts);
                            barChars(b) = categories{i};
                        end
                    end
                end
            end

            bar = barChars;
        end

        function w = getCommandWindowWidth(~)
            % Fallback-safe command window width.
            w = 120;
            try
                sz = matlab.desktop.commandwindow.size;
                % In this environment, the command window size is [cols rows].
                w = sz(1);
            catch
                % keep fallback
            end

            % Avoid pathological tiny widths.
            w = max(w - 1, 60);
        end

        function s = formatTime(~, secs)
            if ~isfinite(secs) || secs < 0
                s = '--:--:--';
                return
            end

            secs = round(secs);
            h = floor(secs / 3600);
            m = floor(mod(secs, 3600) / 60);
            s2 = mod(secs, 60);

            s = sprintf('%02d:%02d:%02d', h, m, s2);
        end

        function txt = truncateText(~, txt, maxLen)
            txt = char(string(txt));

            if maxLen <= 0
                txt = '';
                return
            end

            if length(txt) <= maxLen
                return
            end

            if maxLen <= 3
                txt = txt(1:maxLen);
            else
                txt = [txt(1:maxLen - 3) '...'];
            end
        end

        function c = firstChar(~, value)
            c = char(string(value));
            if isempty(c)
                c = ' ';
            else
                c = c(1);
            end
        end
    end
end
