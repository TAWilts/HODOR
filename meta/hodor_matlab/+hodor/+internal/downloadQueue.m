function [status,message,attempts] = downloadQueue(n,attempt,opts)
%DOWNLOADQUEUE First request every file; retry only unresolved transient failures.
% attempt(index,isFirst) returns status, message, HTTP code, Retry-After seconds.
% All requests are serial. A sweep waits once, rather than once for each file.
arguments
    n (1,1) double {mustBeNonnegative,mustBeInteger,mustBeFinite}
    attempt (1,1) function_handle
    opts.Retries (1,1) double {mustBeNonnegative,mustBeInteger,mustBeFinite} = 5
    opts.SubRetries (1,1) double {mustBeNonnegative,mustBeInteger,mustBeFinite} = 10
    opts.RetryDelay (1,1) double {mustBeNonnegative,mustBeFinite} = 1
    opts.Wait (1,1) function_handle = @pause
end
status = repmat("FAILED",n,1);
message = strings(n,1);
attempts = zeros(n,1);
pending = false(n,1);
retryAfter = zeros(n,1);
for k=1:n
    visit(k,true);
end
for block=1:opts.Retries
    if opts.SubRetries==0 || ~any(pending), break; end
    for sweep=1:opts.SubRetries
        if ~any(pending), break; end
        % Respect the largest server-provided minimum for this sweep.
        opts.Wait(max(opts.RetryDelay,max(retryAfter(pending))));
        for k=find(pending).'
            visit(k,false);
        end
    end
    if any(pending)
        first = find(pending,1);
        warning('hodor:DownloadRetryBlock', ...
            'Retry block %d/%d: %d/%d files still pending after %d retry sweeps. Example: %s', ...
            block,opts.Retries,nnz(pending),n,opts.SubRetries,message(first));
    end
end
% Permanent failures (e.g. 404) are never retried. Keep final failure rows
% and emit at most one additional summary, not one warning per file.
permanent = status=="FAILED" & ~pending;
if any(permanent)
    first = find(permanent,1);
    warning('hodor:DownloadFailed','%d/%d files failed without further retry. Example: %s', ...
        nnz(permanent),n,message(first));
end
if any(pending) && (opts.Retries==0 || opts.SubRetries==0)
    first = find(pending,1);
    warning('hodor:DownloadFailed','%d/%d files failed; retries disabled. Example: %s', ...
        nnz(pending),n,message(first));
end

    function visit(k,first)
        [status(k),message(k),code,delay] = attempt(k,first);
        attempts(k) = attempts(k)+1;
        % A transport exception (NaN code), 2xx incomplete response, timeout,
        % rate limit or server error is retryable; other 4xx/3xx are terminal.
        retryable = isnan(code) || (code>=200 && code<300) || ...
            ismember(code,[408,425,429]) || (code>=500 && code<600);
        pending(k) = status(k)=="FAILED" && retryable;
        if isfinite(delay) && delay>=0
            retryAfter(k) = delay;
        else
            retryAfter(k) = 0;
        end
    end
end
