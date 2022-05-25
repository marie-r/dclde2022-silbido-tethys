function dclde_detections2xml(xml_filename, id, DetPathList, FileStartList, EffStart, EffEnd, DeploymentId, UserId, SpeciesNum)
% dclde_detections2xml - Creates a detections document to represent
%   whistles found by silbido. One XML file represents one area of effort.
%   Concretely DetPathList should contain all detection files within the
%   start and end time.
%
%   xml_filename - Write out Tethys representation of detections to this
%      file.
%   id - Unique string identifying this effort.
%   DetPathList - Cell array of detection files to process
%   FileStartList- A list of serial dates (datenums) representing 
%       the start time of each detection file 
%   EffStart- datenum marking the beginning of recording effort. 
%   EffEnd- Datenum marking the end of recording effort. 
%   DeploymentId - deployment identifier
%   UserID- Character vector of name of User.
%   SpeciesNum - ITIS taxonomic serial number assigned to species

import tonals.TonalBinaryInputStream;

% Bring nilus package classes into current namespace
import nilus.*;
helper = Helper();  % Assists creating elements & marshalling data types

%Kind
speciesNum = helper.toXsInteger(SpeciesNum);
call_type = 'Whistles';

%Create detection document and XML marshaller
detections = Detections(); 
marshaller = MarshalXML();

% Elements that is are complex types or optionally present will not
% present in the nilus representation of the XML schema.  The helper
% can create the mandatory elements for any given level of the document
% automatically.  Here we create the required top-level elements.
helper.createRequiredElements(detections);

detections.setId(id);  % unique document id

% Detections/DataSource is a complex type with children.  It will have
% been created by the helper.  Get the element and then set the foreign 
% key that lets us index into the set of deployments so that we can
% retrieve information about the instrument (e.g. sample rate, depth,
% location)
dataSource = detections.getDataSource();
dataSource.setDeploymentId(DeploymentId);

% Algorithms
% Describe how these detections were done.
algorithm = detections.getAlgorithm();
helper.createRequiredElements(algorithm);
algorithm.setMethod('Li, P., Liu, X., Palmer, K. J., Fleishman, E., Gillespie, D., Nosal, E.-M., Shiu , Y., Klinck, H., Cholewiak, D., Helble, T., and Roch, M. A. (2020). ``Learning Deep Models from Synthetic Data for Extracting Dolphin Whistle Contours,'' in Intl. Joint Conf. Neural Net. (Glasgow, Scotland, July 19-24), pp. 10. DOI:  10.1109/IJCNN48605.2020.9206992');
algorithm.setSoftware('Silbido');
algorithm.setVersion('beta3_0 12811d8');

% Create the algorithm parameters section and retrieve the list
helper.createElement(algorithm, 'Parameters');
param_list = algorithm.getParameters().getAny();

% The helper does not yet let us build nested lists, flatten 
% the sibido parameters. Ideally, this would not be hardcoded, but
% instead read from detection parameters written alongside the detections.
helper.AddAnyElement(param_list, 'advance_ms', '2');
helper.AddAnyElement(param_list, 'length_ms', '8');
helper.AddAnyElement(param_list, 'low_cutofff_Hz', '5000');
helper.AddAnyElement(param_list, 'high_cutofff_Hz', '50000');
helper.AddAnyElement(param_list, 'PeakMethod', 'DeepWhistle');

detections.setUserID(UserId);  % identifier of individual preparing data

%----- When and what were we looking for
effort = DetectionEffort();
% Start/End timespan
iso8601 = 'yyyy-mm-ddTHH:MM:ss.FFFZ';  % ISO 8601 format string
effort.setStart(helper.timestamp(datestr(EffStart, iso8601)));
effort.setEnd(helper.timestamp(datestr(EffEnd, iso8601)));
% Species kinds and calls
kinds = effort.getKind();  % empty linked list
kind = DetectionEffortKind();  % create entry to add to list
helper.createRequiredElements(kind); % popluate mandatory elements
kind.getSpeciesID().setValue(speciesNum);  % taxonomic serial number
kind.getCall().setValue(call_type);  % call type
% Set the granularity to call (requires using the enumerated type)
kind.getGranularity().setValue(GranularityEnumType.fromValue('call'));
% Add the kind to the kind list
kinds.add(kind);

detections.setEffort(effort);

%OnEffort
% Get the on-effort detection group
oneffort = detections.getOnEffort();
% Access the list of detections (empty at first)
detection_list = oneffort.getDetection();
% process the detections, one file at a time
for i = 1:length(DetPathList)
    if rem(i,25) == 0
        fprintf('%d ', i);
    end
    % Load detections and get iterator over the detections
    detstream = TonalBinaryInputStream(DetPathList{i});
    % It is probably more efficient to load all the tonals at once using
    % dtTonalsLoad, but for very large detection files we run out of heap
    % space.
    det_iter = detstream.iterator();
    % Iterate through each detection in the file assigning its time and 
    while det_iter.hasNext()
        %create detection object and mandatory children
        detection = Detection(); 
        helper.createRequiredElements(detection);

        % Access next tonal detection
        tonal = det_iter.next();
        t = tonal.get_time();  % offsets in s
        Hz = tonal.get_freq(); % frequency measurements

        % Determine & populate start/end time
        start = FileStartList(i) + seconds(t(1));
        stop = FileStartList(i) + seconds(t(end));
        detection.setStart(helper.timestamp(datestr(start, iso8601)));
        detection.setEnd(helper.timestamp(datestr(stop, iso8601)));

        % populate species TSN and call type
        detection.getSpeciesID.setValue(speciesNum);
        % Call is a list, create it and populate an instance
        helper.createElement(detection, 'Call');
        callList = detection.getCall(); % Get the empty list
        acall = javaObject('nilus.Detection$Call');  % Create instance of Call
        acall.setValue(call_type); 
        callList.add(acall); %add one call to list

        
        helper.createElement(detection, 'Parameters');
        parameters = detection.getParameters();
        % populate whistle information
        whistle = javaObject('nilus.Detection$Parameters$Tonal');
        % Access lists of time and frequency
        time_list = whistle.getOffsetS();
        freq_list = whistle.getHz();
        t_offset = t - t(1);  % time relative to start
        for meas_idx = 1:length(t)
            time_list.add(t_offset(meas_idx));
            freq_list.add(Hz(meas_idx));
        end
        parameters.setTonal(whistle);
            

        detection_list.add(detection);
        1;
    end
end
fprintf('processed %d files\n', length(DetPathList));
marshaller.marshal(detections, xml_filename)
end


