gps = readtable('D:\dclde2022\detections\metadata\metadata_DCLDE_LaskerGPS.csv');

%gps = sortrows(gps, 'GpsDate');
field = 'UTCTime';
gps = sortrows(gps, field);
tolerance = duration(4, 0, 0);  % h, m, s

% difference between consecutive GPS measurements
delta = diff(gps.(field));
exceedsP = delta > tolerance;

problems_at = find(exceedsP);
[gps.(field)(problems_at), gps.(field)(problems_at+1)]

