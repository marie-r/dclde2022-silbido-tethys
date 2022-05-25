function [day, night] = effort_diel(query_h, timestamp, lat, long, verbosity)
% [day, night] = effort_diel(query_h, timestamp, lat, long)
% Given a set of UTC timestamps, latitudes, and longitudes,
% return two sets of indices indicating ranges of day night.
%
% Inputs:
% query_h - query handler, see dbInit
% timpestamp - Nx1 Matlab serial dates (datenum)
% lat - Nx1 latitutde (degrees N)
% long - Nx1 longitude (degrees E)
% verbosity - 0 (no information) through 2
% 
% Outputs:
% day - Matrix with two columns.  Observations between the first and
%    second column occur during the day, e.g. [8 15] indicates that
%    lat(8:15), long(8:15) were visited after sunrise and before
%    sunset  Each row represents a set of daytime observations.
% night - Matrix with two columns.  Similar to day, except this represents
%    observations between sunset and sunrise.
%
% In general, we look for lat/long groups that are no more than
% a couple degrees distance from one another (controlled by tolerance
% in the code).  We then query the ephemeris service to find out when
% the sun is up and down, then break up the long/lat within this segment.
%
% CAVEATS:  If the timestamps have a gap in them but the observation
% platform has not moved, the output may not be what is expected.
% 
% Example of time gap:
% UTC timestamps:  03-Sep-2017 05:35:05 - 04-Sep-2017 18:52:39 
% for a region that has the following night time periods
% 03-Sep-2017 05:35:05 - 03-Sep-2017 16:17:05
% 04-Sep-2017 04:45:05 - 04-Sep-2017 16:19:05
%
% If effort stopped a couple hours into the night, and then resumed
% the next morning, the indices stored in the day/night
% arrays would reflect this.  For example, the timestamps associated with
% the day and night entries might show a grap between the stop time
% (2017-09-03 07:16:43) and starting recording again in the morning
% (2017-09-04 16:29:42).


narginchk(4, 5);
if nargin < 5
    verbosity = 0;  % debug verbosity 1 standard, 2 very
end

N = length(lat);  % Number of latitude entries

if length(long) ~= N || length(timestamp) ~= N
    error('timestamp, lat, and long must be of the same length');
end

daynight{1} = zeros(0,2);  % day
daynight{2} = zeros(0,2);  % night

% When the distance changes by more than this many degrees, we recenter
% our observations to account for difference in sunrise/sunset based
% on longitude and latitude.
tolerance = 2;

if N > 1
    latlong = [lat(:), long(:)];
    % Compute distances between observations
    deltas = distance(latlong(1:N-1, :), latlong(2:N,:));

    total_dist = cumsum(deltas);
    first = 1;
    idx = 1;
    last_dist = 0;
    done = false;
    groups = 0;
    ranges = zeros(0, 2);  % empty matrix
    centers = zeros(0, 2);  % centers of lat/longs
    while ~ done
        while idx < N && total_dist(idx) - last_dist < tolerance
            idx = idx + 1;
        end
        
        % total_dist is from 1 to N-1.  If we are at N-1, throw in
        % the last observation even if it is a little farther away
        % (unlikely in a regularly spaced GPS track)
        if idx + 1 >= N
            done = true;
            last = N;
        else
            last = idx;
        end
        
        groups = groups + 1;  % count number of groups
        span = first:last;
        % These indices cover the current set
        % datestr(timestamp(span))
        % latlong(span, :)
        center = mean(latlong(span, :), 1);
        centers(end+1,:) = center;
        
        ranges(end+1,:) = [first, last];
        fprintf('%s to %s centered at ', ...
            datestr(timestamp(first)), datestr(timestamp(last)))
        fprintf('%.3f ', center);
        fprintf('\n');
        % set up next 
        if ~ done
            idx = idx + 1;
            first = idx;
            last_dist = total_dist(first);
        end
    end
else
    % Only one entry
    centers = [lat, long];
    ranges = [1, 1];  
end

% Query diel information
for ridx = 1:size(ranges, 1)
    start = ranges(ridx, 1);
    stop = ranges(ridx, 2);
    night = dbDiel(query_h, centers(ridx,1), centers(ridx, 2), ...
        timestamp(start), timestamp(stop));
    
    if verbosity
        offset = dbTimeZone(query_h, centers(ridx,1), centers(ridx, 2));
        fprintf('Group %d UTC %s - %s Local time is Z%d\n', ridx, ...
            datestr(timestamp(start)), datestr(timestamp(stop)), offset);
            
        if size(night, 1) == 0
            fprintf('No nights during span\n');
        else
            fprintf('Night time\n');
            for idx=1:size(night, 1)
                fprintf('night %s - %s\n', ...
                    datestr(night(idx,1)), datestr(night(idx,2)));
            end
        end
    end
    if isempty(night)
        % everything is during the day
        daynight{1}(end+1, :) = [start, stop];
    else
        current = start;
        nightsN = size(night, 1);
        night(end+1, :) = [Inf, Inf];  % Add bound to end
        
        current = start;
        first = current; % first index in day/night
        nidx = 1;  % index to night timestamps
        while current <= stop
            last = current;
            tstamp = timestamp(current);

            % If there is no gap in the time record, we should transition
            % to the next day or night (~ isnight) after completing
            % processing of a day or night.  However, it is possible that
            % we could have gone off effort for a period of time.  Make
            % sure that we have the appropriate night index and set the
            % time
            while timestamp(current) > night(nidx, 2)
                nidx = nidx + 1; 
            end
            isnight = timestamp(current) >= night(nidx, 1);
            
            if ~ isnight
                % daytime, move into the current night
                while tstamp < night(nidx,1) && current <= stop
                    if verbosity > 1&& nidx <= nightsN
                        fprintf('%d=%s < %s sunset\n', ...
                            current, datestr(timestamp(current)), ...
                            datestr(night(nidx, 1)));
                    end
                    last = current;
                    current = current + 1;
                    tstamp = timestamp(current);
                end
                if verbosity, showspan('adding day', timestamp, first, last), end
                daynight{1}(end+1, :) = [first, last];
            else
                % nighttime
                while tstamp <= night(nidx, 2) && current <= stop
                    if verbosity > 1 && nidx <= nightsN
                        fprintf('%d=%s < %s end of night\n', ...
                            current, datestr(timestamp(current)), ...
                        datestr(night(nidx, 2)));
                    end
                    last = current;
                    current = current + 1;
                    tstamp = timestamp(current);
                end
                nidx = nidx + 1;  % finished this night, onto the next
                if verbosity, showspan('adding night', timestamp, first, last), end
                daynight{2}(end+1, :) = [first, last];
            end
            first = current;
            
        end
    end
end

if verbosity
    % data summary
    for diel=1:2
        indices = daynight{diel};
        if diel == 1
            fprintf('daytime\n')
        else
            fprintf('nighttime\n');
        end
        for idx = 1:size(daynight{diel}, 1)
            fprintf('%s - %s\n', datestr(timestamp(indices(idx,1))), ...
                datestr(timestamp(indices(idx,2))));
        end
        
    end
end

% Copy to outputs
day = daynight{1};
night = daynight{2};
1;

function showspan(msg, timestamps, first, last)
% showspan(msg, timestamps, first, last)
% provide information about a timespan

fprintf('%s [%d=%s - %d=%s]\n', msg, ...
    first, datestr(timestamps(first)), ...
    last, datestr(timestamps(last)));



