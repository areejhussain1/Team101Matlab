%% Senior Design FRF Plot
%clear
%clc
%close all

%data = readmatrix('11_18_1_undamped.txt');
data = readmatrix("AmplitudeBareBar.txt");
data = data(1:end, :);

freq = data(:,1);
mag = data(:,2);
dB = 20*log10(abs(mag));


[max_mag, i] = max(mag);
peak_f = freq(i);

hp_mag = max_mag / sqrt(2);

[~, i_left] = min(abs(mag(1:i) - hp_mag));
f1 = freq(i_left);

[~, i_right_rel] = min(abs(mag(i:end) - hp_mag));
i_right = i + i_right_rel - 1;
f2 = freq(i_right);


df   = f2 - f1;
eta  = df / peak_f; 
zeta = df / (2*peak_f);

fprintf('Loss Factor = %.4f\n', eta);
fprintf('Damping Ratio = %.4f\n', zeta);

figure
plot(freq, dB/5 - 15);
grid on;
xlabel('Frequency (Hz)');
ylabel('Magnitude (dB)');
xline(peak_f, "r--")
%xline(f1, "b--")
%xline(f2, "b--")
title('FRF Undamped Ansys');
xlim([0 500])
legend("", "Peak Frequency: " + peak_f + " Hz", "f1", "f2");





