function psdplotdb(az_g,name)
%close all

% Acceleration data vector
% Replace this with your actual data
%accel = your_accel_data;   % e.g. accel = data(:,1);

% Sampling frequency
Fs = 6400;  % Hz

% Welch parameters
window = hamming(1024);    % window length
noverlap = 512;            % 50% overlap
nfft = 1024;               % FFT length
L=numel(az_g);
maxNperseg = 2^14;                           % 16384
nperseg = min(maxNperseg, max(256, floor(L/8)));
nperseg = min(nperseg, L);


% Plot PSD using pwelch
% figure;
%[pxx,f,pxxc] = pwelch(az_g, window, noverlap, nfft, Fs,'ConfidenceLevel',.95);
[pxx,f,pxxc] = pwelch(az_g, nperseg, noverlap, nfft, Fs,'ConfidenceLevel',.95);
% grid on;
% title('Power Spectral Density of Acceleration Signal');
% xlabel('Frequency (Hz)');
% ylabel('Power/Frequency (dB/Hz)');

% figure;
% plot(f,pxx, 'LineWidth', 1);
% grid on;
% hold on;
% plot(f,pxxc,'-.')
% xlim([0 500]);
% 
% title('Power Spectral Density of Acceleration Signal with ±95% confidence Bounds');
% xlabel('Frequency (Hz)');
% ylabel('PSD (G^2/Hz)');
% 
% % Force MATLAB not to use ×10^n axis notation
% ax = gca;
% ax.XAxis.Exponent = 0;

% PLOT IN DB
figure;
plot(f,10*log10(pxx), 'LineWidth', 1);
grid on;
hold on;
plot(f,10*log10(pxxc),'-.')
xlim([0 500]);

title("PSD of " + name + " with ±95% confidence Bounds");
xlabel('Frequency (Hz)');
ylabel('PSD (dB/Hz)');

% Force MATLAB not to use ×10^n axis notation
ax = gca;
ax.XAxis.Exponent = 0;
end