function child = createSubclass(instance, subclass)
% child = createSubclass(instance, subclass)
% public Java subclasses cannot be easily created in Matlab
% It requires us to get the list of subclasses and then create it
%
% This function returns a new instance of the specified public subclass

% Obtain list of nested classes
nested_classes = instance.getClass().getClasses();

child = [];  % assume failure

% List of names for letting users know what they should have
% used if they provided a bad value.
names = cell(length(nested_classes), 1);

% Loop through nested classes to find correct one.
for idx = 1:length(nested_classes)
    % Pull out the name
    name = string(nested_classes(idx).getCanonicalName());
    parts = name.split('.');
    names{idx} = parts{end};
    % Create the instance if it is what we want
    if strcmp(parts{end}, subclass)
        child = nested_classes(idx).newInstance();
        break
    end
end

if isempty(child)
    % bad subclass
    classes = strjoin(names, ', ');
    error('Expected subclass %s, given %s', classes, subclass);
end

    

