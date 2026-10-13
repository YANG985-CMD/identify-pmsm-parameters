function fingerprint = pmsm_fingerprint(data, names)
%PMSM_FINGERPRINT Hash required numeric signal values, independent of filenames.
arguments
    data table
    names cell
end
digest = javaMethod('getInstance','java.security.MessageDigest','SHA-256');
values = double(data{:,names});
digest.update(typecast(uint64(size(values)), 'int8'));
digest.update(typecast(values(:), 'int8'));
raw = typecast(digest.digest(), 'uint8');
fingerprint = string(lower(reshape(dec2hex(raw,2).',1,[])));
end
