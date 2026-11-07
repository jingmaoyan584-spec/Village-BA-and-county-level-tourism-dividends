Kernel weights: exp(-lambda*distance), lambda=1; donor weights normalized to sum to one.
Distance is Euclidean distance in the eight-dimensional standardized pre-treatment feature space.
Bootstrap: 1000 donor-county resamples with replacement; all feature construction, standardization, weighting, and TWFE estimation repeated each draw.
