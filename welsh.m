% Acceleration data vector
% Replace this with your actual data
%accel = your_accel_data;   % e.g. accel = data(:,1);

% Sampling frequency
Fs = 6400;  % Hz

% Welch parameters
window = hamming(1024);    % window length
noverlap = 512;            % 50% overlap
nfft = 1024;               % FFT length

% Plot PSD using pwelch
figure;
pwelch(az_g, window, noverlap, nfft, Fs);
grid on;
title('Power Spectral Density of Acceleration Signal');
xlabel('Frequency (Hz)');
ylabel('Power/Frequency (dB/Hz)');