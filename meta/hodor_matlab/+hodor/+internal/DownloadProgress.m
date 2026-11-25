classdef DownloadProgress < handle
    %DOWNLOADPROGRESS Isolate optional console rendering from transfer logic.
    properties (SetAccess=private)
        Enabled (1,1) logical = false
    end
    properties (Access=private)
        Bar = []
        Completed (1,1) double = 0
    end
    methods
        function obj = DownloadProgress(total,enabled)
            if ~enabled || total==0, return; end
            try
                obj.Bar = hodor.internal.vendor.FanCmdWaitbar(total, ...
                    'title','HODOR','showTime',true);
                obj.Enabled = true;
            catch
                % Rendering must never prevent downloading.
                obj.Bar = [];
            end
        end
        function update(obj,completed,topic)
            if ~obj.Enabled, return; end
            try
                if completed>obj.Completed
                    obj.Bar.step(completed,topic);
                    obj.Completed = completed;
                else
                    % Status updates do not increment completion or corrupt ETA.
                    obj.Bar.step("status",topic);
                end
            catch
                obj.Enabled = false;
                obj.Bar = [];
            end
        end
        function clearLine(obj)
            if ~obj.Enabled, return; end
            try
                obj.Bar.clc();
            catch
                obj.Enabled = false;
                obj.Bar = [];
            end
        end
    end
end
