

% Demonstration of using the Nilus library to generate deployment
% information from NOAA cruises using a spreadsheet with cruise information
% Taken from the DCLDE 2022 data set.

import nilus.*

% Data location
metadata_loc = 'U:\corpora-old\dclde2022';
% Output location
xml_loc = fullfile(metadata_loc, 'xml', 'deployments');
% source metadata in files:
% spreadsheet - array configuration information
% .csv files - GPS tracks
% DCLDE metadata was missing some points, we use the complete
% ship track files AllLasker_gpsData, AllSette_gpsData
spreadsheet = 'metadata_DCLDE2020 DetectionData.xlsx';

projects = ["1705_Array", "1706_Array"];
cruises = ["Lasker", "Sette"];

% Several details for this dataset were described textually and
% are repeated here.  We do not reproduce the the array geometry
% as it is beyond the scope of the demonstration project for which
% this conversion was created. We also do not process the depth data
% which are available.
% See https://www.soest.hawaii.edu/ore/dclde/dataset/ for details

Fs = 500000;  % acoustic sample rate in Hz
bits = 16;  % acoustic sample quantization

marshaller = MarshalXML();
helper = Helper();

degrees = 360;  % degrees around the globe

for pidx = 1:length(projects)
    % Get information about deployments on current ship from specified
    % sheet
    efforts = readtable(fullfile(metadata_loc, spreadsheet), ...
        'Sheet', projects(pidx), 'TreatAsMissing', 'NA');
    fields = efforts.Properties.VariableNames;
    
    % Get GPS information for ship
    complete_gps = true;
    if complete_gps
        utc_field = 'GpsDate';  % timestamp field
        gps_file = sprintf('All%s_gpsData.csv', cruises(pidx));
    else
        % Partial GPS distributed with DCLDE
        utc_field = 'UTCTime'; % timestamp field
        gps_file = sprintf('metadata_DCLDE_%sGPS.csv', cruises(pidx));
    end
    gps_path_to_file = fullfile(metadata_loc, gps_file);
    gps = readtable(gps_path_to_file);
    
    % data cleaning
    % Remove bad rows
    gps(gps.Latitude == 0 & gps.Longitude == 0, :) = [];
    % Remove duplicate timestamps and ensure that everything is sorted
    [~,indices] = unique(gps.(utc_field));
    gps = gps(indices, :);
    % Tethys expects Longitude in degrees east
    deg = 360;
    gps.Longitude = rem(gps.Longitude + deg, deg);
        
    % identify fields that contain channel information
    % NOAA set these up as hpN_AD where N is the hydrophone number
    % ch_fields will contain the indices of the first channel specific
    % information field, e.g. hp1_dist, the distance between the ship's
    % GPS receiver and the the array element
    ch_fields = find(cellfun(@(x) contains(x, '_dist'), fields) > 0);
    for eidx = 1:height(efforts)
        effort_start = efforts.ArrayStart_UTC(eidx);
        effort_end =  efforts.ArrayEnd_UTC(eidx);
        
        fprintf('%s %d/%d:   %s\t\t%s\n', projects(pidx), ...
            eidx, height(efforts), ...
            effort_start, effort_end);
        drawnow('update');
        
        % Create a deployment for this effort
        d = Deployment();
        helper.createRequiredElements(d);
        
        % Construct a unique id for this deployment
        % We assume here that the array will not be put into the water
        % more than once on the same day, if not add HHMM to make it
        % unique.
        d.setId(sprintf('%s-%s', projects(pidx), ...
            datestr(effort_start, 'YYYY-mm-dd')));
        
        % Populate inofrmation about project, deployment, and cruise
        d.setProject('DCLDE2022');
        d.setDeploymentId(eidx);
        d.setCruise(cruises(pidx));
        
        d.setPlatform('towed array');
        
        % Describe the arrays
        instrument = d.getInstrument();
        instrument.setType('inline multichannel array');
        instrument.setInstrumentId(sprintf('%s, %s', ...
            efforts.Array1{eidx}, efforts.Array2{eidx}));
        
        % Populate information for each channel
        % In general, Nilus (and the JAXB XJC compiler that generates
        % the Nilus classes from the schemata) treats elements that can
        % occur more than once as a list.  In these cases, we get the
        % element and it returns a list to which we add things.
        hydrophones = [];
        sampling_details = d.getSamplingDetails();
        channel_list = sampling_details.getChannel();  % empty list for now
        for cidx = ch_fields
            if ~ isnan(efforts.(fields{cidx})(eidx))
                % extract channel/hydrophone number
                m = regexp(fields{cidx}, ...
                    '[^\d]+(?<hydrophone>\d+)[^\d]+', 'names');
                h_id = str2num(m.hydrophone);
                % Keep hydrophone number for later
                % For this analysis, hydrophone number and channel number
                % are synonymous.
                hydrophones(end+1) = h_id;
                % Convert channel start/end recording time to required
                % format
                start_time = helper.timestamp(...
                    datestr(efforts.ArrayStart_UTC(eidx), ...
                    'YYYY-mm-ddTHH:MM:SS.FFFZ'));
                end_time = helper.timestamp(...
                    datestr(efforts.ArrayEnd_UTC(eidx), ...
                    'YYYY-mm-ddTHH:MM:SS.FFFZ'));
                
                % Create and populate the channel information
                channel = ChannelInfo();
                channel.setChannelNumber(helper.toXsInteger(h_id))
                channel.setSensorNumber(h_id);
                
                channel.setStart(start_time);
                channel.setEnd(end_time);
                
                % Set up sampling and gain regimens
                % There are nested classes in Nilus, e.g.
                % nilus.ChannelInfo$Sampling.  Unfortunately, the Matlab
                % interface does not allow us to access these directly and
                % we use a function to do this
                
                sampling = createSubclass(channel, 'Sampling');
                channel.setSampling(sampling);
                
                % specify sampling regimen and add it to Sampling
                regimen = createSubclass(sampling, 'Regimen');
                regimen.setTimeStamp(start_time);
                regimen.setSampleBits(bits);
                regimen.setSampleRateKHz(Fs / 1000.0)
                % Add Sampling/Regimen
                regimen_list = sampling.getRegimen();
                regimen_list.add(regimen);
                
                
                gain = createSubclass(channel, 'Gain');
                channel.setGain(gain);
                
                regimen = createSubclass(gain, 'Regimen');
                regimen.setTimeStamp(start_time);
                dB = efforts.(sprintf('hp%d_AD', h_id))(eidx);
                regimen.setGainDB(helper.toXsDouble(dB));
                % Add Gain/Regimen
                regimen_list = gain.getRegimen();
                regimen_list.add(regimen);
                
            end  % hydrophone sampling details
            
            % If we wanted to add QualityAssurance fields, we could do
            % so here.
            
            % Populate deployment data, e.g. tracklines
            data = d.getData();
            tracks = createSubclass(data, 'Tracks');
            data.setTracks(tracks);
            % identify GPS points that lie within the  effort
            [first, last] = binary_search(effort_start, effort_end, gps.(utc_field));
            
            % Create a track object to associate with the trackline
            % information
            track_list = tracks.getTrack();
            
            % We do not have individual tracklines, so all GPS data between
            % the start and end time will go in the same set of points
            % Create track information and add it to the deployment
            track = createSubclass(tracks, 'Track');
            track_list.add(track);
            
            % The GPS sampling frequency of these deployments is much
            % higher than the rate of change.  We decimate the time
            % series to a lower resolution and convert to degrees East
            % We assume that the data are sampled regularly, but
            % the resampling algorithm will handle irregularly spaced data
            % if called with appropriate arguments
            % The timetable data type was introduced in 2016b
            range = first:last;
            % Extract relevant range
            timestamps = gps.(utc_field)(range);
            longitude = gps.Longitude(range);
            latitude = gps.Latitude(range);
            series = timetable(timestamps, longitude, latitude, ...
                'VariableNames', {'Longitude', 'Latitude'});
            % resampling and filling in gaps
            interval = minutes(5);
            dseries = retime(series, 'regular', 'spline', 'TimeStep', interval);
            
            point_list = track.getPoint();
            % Convert UTC to ISO8601 strings
            utc_strings = dbSerialDateToISO8601(dseries.timestamps);

            for gidx = 1:height(dseries)
                point = createSubclass(track, 'Point');
                point.setLatitude(helper.toXsDouble(dseries.Latitude(gidx)));
                point.setLongitude(helper.toXsDouble(dseries.Longitude(gidx)));
                point.setTimeStamp(helper.timestamp(utc_strings{gidx}));
                point_list.add(point);
            end
            
            channel_list.add(channel);
        end % channel
        
        % Populate deployment and recovery information
        
        deployment_info = d.getDeploymentDetails();
        deployment_info.setLatitude(gps.Latitude(first));
        % Add trip around Earth and take modulo.  This will
        % convert negative degrees to positive degrees east
        degEast = rem(gps.Longitude(first)+degrees, degrees);
        deployment_info.setLongitude(degEast);
        deployment_info.setTimeStamp(start_time);
        deployment_info.setAudioTimeStamp(start_time);
        deployment_info.setVessel(cruises(pidx));
        
        % Recovery details is not mandatory as an instrument could still
        % be in the water.  Therfore we create it
        recovery_info = DeploymentRecoveryDetails();
        d.setRecoveryDetails(recovery_info);
        recovery_info.setLatitude(gps.Latitude(last));
        % Add trip around Earth and take modulo.  This will
        % convert negative degrees to positive degrees east
        degEast = rem(gps.Longitude(last)+degrees, degrees);
        recovery_info.setLongitude(degEast);
        recovery_info.setTimeStamp(start_time);
        recovery_info.setAudioTimeStamp(end_time);
        recovery_info.setVessel(cruises(pidx));
        
        % Sensors
        % We do not have all of the information to populate this correctly.
        sensors = d.getSensors();
        audio_list = sensors.getAudio();
        for hidx = hydrophones
            audio = Audio();
            audio.setNumber(helper.toXsInteger(hydrophones(hidx)));
            % We do not have a serial number for the sensor assembly, use unit
            % number
            audio.setSensorId(sprintf('%d', hydrophones(hidx)));
            audio.setHydrophoneId('HTI-96-min');
            audio.setPreampId('custom');
            audio.setDescription('Arrays used HTI-96-min hydrophones and custom-built pre-amplifiers with combined average measured sensitivity of -144dB +/- 5dB re: 1V/uPa from 2-100 kHz and approximately linear roll-off to -156 dB +/- 2 dB re 1V/ uPa at 150kHz. The hydrophones have a strong high-pass filters at 1600 Hz to reduce low-frequency flow noise and ship noise, reducing sensitivity by 10dB at 1000 Hz. The acoustic DAQ sampled all six channels simultaneously at 500 kHz sample rate and applied 0-12 dB of gain to the incoming signal from each hydrophone. The preamplifier gain specific to each hydrophone and any additional gain applied to each channel through the DAQ during real-time monitoring is detailed in the metadata file provided.');
            % Geometry is available and would be populated here.
            audio_list.add(audio);
            
            
        end
        
        % This section is very specific to the DCLDE data set.  They had
        % one depth sensor per array and one or two arrays.  As there were
        % three hydrophones per array, we determine the number of depth
        % sensors based on the number of hydrophones.
        depth_list = sensors.getDepth();
        for dix = 1:floor(length(hydrophones)/3)
            depth = GenericSensor();
            % Depth sensors numbered the same as hydrophones
            depth.setNumber(helper.toXsInteger(hydrophones(hidx)));
            % No serial number, use unit number
            depth.setSensorId(sprintf('%d', hydrophones(hidx)));
            description = 'The inline and end arrays contained a Kellar (PA7FLE) or Honeywell (PX2EN1XX200PSCHX) depth sensor, with depth recorded every second with a voltage MicroDAQ (max voltage +/- 2V).  Depth data collected aboard the ';
            switch cruises(pidx)
                case 'Lasker'
                    description = [description, 'R/V Lasker were 16-bit (model USB-1608G).'];
                case 'Sette'
                    description = [description, 'R/V Sette were collected at 12-bit (model USB-1208LS).'];
            end
            depth.setDescription(description)
            % Geometry is roughly available and would be populated here.
            depth_list.add(depth);
        end
        
        
        xml_file = sprintf('%s.xml', d.getId());
        marshaller.marshal(d, fullfile(xml_loc, xml_file));
        1;    
    end  % effort
end  % projects
