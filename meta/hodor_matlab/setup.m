function setup()
%SETUP Add the HODOR MATLAB package folder to the MATLAB search path.
folder = fileparts(mfilename('fullpath'));
addpath(folder);
fprintf('HODOR MATLAB tools added: %s\n',folder);
end
