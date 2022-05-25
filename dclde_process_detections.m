function dclde_process_detections
% dclde_process_detections
% Custom Matlab script for converting silbido format detections
% to Tethys
% 
% This is a one off script designed for the DCLDE 2022 data set,
% but can be adapted to convert detections in general.

base_dir = 'D:/dclde2022';
% source and output directories
detections_dir = fullfile(base_dir, 'detections');
out_dir = fullfile(detections_dir, 'metadata', 'detections');

% Tethys server, modify host name as appropriate
q = dbInit('Server', 'localhost');

project = 'DCLDE2022';
% Get information about Tethys deployments
dep = dbDeploymentInfo(q, 'Project', project);
ids = string(arrayfun(@(x) x.Id, dep));
starts = arrayfun(@(x) x.DeploymentDetails.AudioTimeStamp, dep);
starts = datetime(vertcat(starts{:}), 'ConvertFrom', 'datenum');
stops = arrayfun(@(x) x.RecoveryDetails.AudioTimeStamp, dep);
stops = datetime(vertcat(stops{:}), 'ConvertFrom', 'datenum');
cruise = string(arrayfun(@(x) x.Cruise, dep));
deployments = table(ids, cruise, starts, stops);

cruises = ["Lasker", "Sette"];
directories = ["1705", "1706"];
preparer = 'pconant';  % person who prepared data

species = 180404;  % odontocetes
for cruise_idx = 1:length(cruises)
    path = fullfile(detections_dir, char(directories(cruise_idx)));
    % Get detection files 
    [paths,names,~] = utFindFiles('*.det', {path}, 1);
    
    [paths, timestamps] = getSortedNames(paths, names);

    % DCLDE 2022 files are one minute apart.
    % Find contiguous regions that are a single effort unit
    delta = diff(timestamps);
    maxgap = duration(0,1,59);
    boundaries = [1; find(delta > maxgap)+1];

    % toodo: cruise_idx 2 group_idx 12 fails java heap error about 500
    % files in
    for group_idx = 1:length(boundaries)
        start = boundaries(group_idx);
        if group_idx == length(boundaries)
            stop = length(paths);  % last group
        else
            stop = boundaries(group_idx+1) - 1;
        end
        % If there are very many detections, we can run into heap issues
        % generating the XML.  The right thing to do would be to split
        % the group intelligently, paying attention to how many whistles
        % are in each file.  Here we simply split based on number of files
        % without worrying about how many whistles are in each file
        groupbyN = 120;
        fprintf('group %d/%d %d files\n', ...
            group_idx, length(boundaries), stop-start+1);
        if (stop - start) > groupbyN
            stop_intermediate = start+groupbyN-1;
            while start <= stop
                range = start:stop_intermediate;
                process_detections(out_dir, project, cruises(cruise_idx), ...
                    paths(range), timestamps(range), ...
                    start, stop, deployments, preparer, species);
                start = start+groupbyN;
                stop_intermediate = min(stop, start+groupbyN-1);
            end
        else
            range = start:stop;
            process_detections(out_dir, project, cruises(cruise_idx), ...
                paths(range), timestamps(range), ...
                start, stop, deployments, preparer, species);
        end
    end
end


function [paths, timestamps] = getSortedNames(paths, names)
% [paths, timestamps] = getSortedNames
% Extract timestamps from file names and return filepaths
% sorted by time and their associated timestampd
% paths - full path to file
% names - filename only

% Pull timestamps from file names.  
% DCLDE 2022 filesnames have pattern _YYYYMMDD_HHMMSS_FFF
match = regexp(names,  '\d+_(?<timestamp>\d+_\d+_\d+)', 'names');
% Make sure we were able to find the timestamps in filenames
failures = cellfun(@isempty, match);
if any(failures)
    error('Unable to extract timestamps for files\n%s\nEnd unable to extract timestamps', ...
        strjoin(names(failures), '\n'));
end
% collect timestamp strings from cells and parse into datetimes
date_str = string(cellfun(@(x) x.timestamp, match, ...
    'UniformOutput', false));
timestamps = datetime(date_str, 'InputFormat', 'yyyyMMdd_HHmmss_SSS');

% Sort by timestamp
if ~ issorted(timestamps)
    [timestamps, permutation] = sort(timestamps);
    % Reorder files to match sort order
    paths = paths(permutation);
end

function process_detections(out_dir, project, cruise, paths, timestamps, start, stop, deployments, preparer, species)
% process_detections
% Generate a detection document.
% Each document has a unique id and filename based on the project,
% the name and the start time.  
% 
% out_dir - directory in which to store the detection document
% project - overall project identifier
% cruise - cruise or other identifying string
% paths - list of detection files
% timestamps - start time of each detection file
% start - effort start
% stop - effort end
% deployments - Information about deployments, we query this to find
%    the correct deployment to associate with the detection effort
% preparer - Person who conducted the analysis
% species - species identifier (ITIS taxonomic serial number)

file_duration = seconds(60);  % DCLDE 2022 files are this many s long
id = sprintf('%s_silbido_%s_%s', project, cruise, ...
    datestr(timestamps(1), 'yyyy-mm-ddTHH-MM'));

% Identify the deployment with which these detections are associated
% We assume that any date within start and stop falls within a single
% deployment.
deployment = deployments( ...
    deployments.cruise == cruise & ...
    deployments.starts <= timestamps(1) & ...
    deployments.stops >= timestamps(1), :);

xml_file = fullfile(out_dir, sprintf('%s.xml', id));
start_eff = timestamps(1);
end_eff = timestamps(end)+file_duration;
fprintf('processing %d files into %s. Effort %s - %s\n', length(paths), ...
    xml_file, start_eff, end_eff);

showonly = false;
if ~ showonly
    dclde_detections2xml(xml_file, id, ...
        paths, timestamps, start_eff, end_eff, ...
        deployment.ids, preparer, species);
end