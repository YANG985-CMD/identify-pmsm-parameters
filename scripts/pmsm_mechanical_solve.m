function [theta,diagnostics,status] = pmsm_mechanical_solve(matrix,y,maxCondition,strictPositive)
%PMSM_MECHANICAL_SOLVE Scaled SVD rank audit followed by linear least squares.
n = size(matrix,2); theta = nan(n,1); status = "not_identifiable";
scale = vecnorm(matrix,2,1); scale(scale == 0) = 1;
scaled = matrix./scale;
rankValue = 0; condition = Inf; singularValues = []; residualRMSE = NaN;
if size(matrix,1) >= n && n > 0
    singularValues = svd(scaled,0);
    rankValue = sum(singularValues > max(size(scaled))*eps(max(singularValues)));
    if rankValue == n
        condition = singularValues(1)/singularValues(end);
        if condition <= maxCondition
            theta = (scaled\y)./scale.';
            status = "estimated_unvalidated";
            if any(~isfinite(theta)) || any(theta(strictPositive == 1) <= 0) || any(theta(strictPositive == 0) < 0)
                status = "nonphysical";
            end
            residualRMSE = sqrt(mean((y-matrix*theta).^2));
        else
            status = "ill_conditioned";
        end
    end
end
diagnostics = struct('rank',rankValue,'unknownCount',n,'scaledCondition',condition, ...
    'singularValues',singularValues,'columnScales',scale,'residualRMSE',residualRMSE);
end
