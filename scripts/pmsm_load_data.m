function data = pmsm_load_data(source)
%PMSM_LOAD_DATA Read a table, CSV, or MAT file containing a table named data.
arguments
    source
end
if istable(source)
    data = source;
elseif (isstring(source) && isscalar(source)) || (ischar(source) && isrow(source))
    file = char(source);
    [~,~,extension] = fileparts(file);
    switch lower(extension)
        case '.csv'
            data = readtable(file, VariableNamingRule='preserve');
        case '.mat'
            loaded = load(file, 'data');
            if ~isfield(loaded, 'data') || ~istable(loaded.data)
                error('pmsm:DataType', 'MAT file must contain a table named data.');
            end
            data = loaded.data;
        otherwise
            error('pmsm:FileType', 'Use a CSV or MAT file, or a MATLAB table.');
    end
else
    error('pmsm:DataType', 'Input must be a table or a file path.');
end
end
