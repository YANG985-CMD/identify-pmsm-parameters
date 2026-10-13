function voltage = pmsm_predict_voltage_error(network, currentAmps)
%PMSM_PREDICT_VOLTAGE_ERROR Infer inside the independently calibrated current range.
arguments
    network (1,1) struct
    currentAmps double {mustBeReal,mustBeFinite}
end
if any(currentAmps(:) < network.currentRangeAmps(1) | currentAmps(:) > network.currentRangeAmps(2))
    error('pmsm:CalibrationRange','Current exceeds calibration range; no silent extrapolation.');
end
% JSON round-trips do not preserve a vector's row/column orientation.
hidden = tanh(network.weightsInput(:)*(currentAmps(:).'/network.inputScale)+network.biasHidden(:));
prediction = network.outputScale*(network.weightsOutput(:).'*hidden+network.biasOutput);
voltage = reshape(prediction,size(currentAmps));
end
