import serial
import time
import matplotlib.pyplot as plt
from serial.serialutil import SerialException

# -------------------
# USER SETTINGS
# -------------------
COM_PORT = "COM3"          # <-- change to your Pico's COM port
BAUDRATE = 115200
DURATION_SEC = 10          # how long to record data for
SENSOR_ID = 0              # which sensor_id to plot (0 for now)

# ADXL372 raw code ~ 0.1 g per count (100 mg/LSB)
LSB_TO_G = 0.1


def main():
    print(f"Opening {COM_PORT} at {BAUDRATE} baud...")
    try:
        ser = serial.Serial(COM_PORT, BAUDRATE, timeout=1)
    except SerialException as e:
        print("Could not open serial port:", e)
        return

    # Give Pico a moment and flush any junk
    time.sleep(1.0)
    ser.reset_input_buffer()

    print("Waiting for header line (timestamp_us,...) ...")
    header_seen = False
    try:
        while True:
            try:
                raw = ser.readline()
            except SerialException as e:
                print("Serial read error while waiting for header:", e)
                ser.close()
                return

            if not raw:
                # just a timeout, keep looping
                continue

            line = raw.decode("utf-8", errors="ignore").strip()
            print("RX:", line)  # Debug: see what’s coming in
            if line.startswith("timestamp_us"):
                header_seen = True
                print("Header detected, starting capture...")
                break
    except KeyboardInterrupt:
        print("Interrupted while waiting for header.")
        ser.close()
        return

    if not header_seen:
        print("Never saw header line. Is the Pico running the monitor firmware?")
        ser.close()
        return

    t_list = []
    xg_list = []
    yg_list = []
    zg_list = []
    t_start = None

    print(f"Capturing for {DURATION_SEC} seconds... (Ctrl+C to stop early)")
    t_capture_start = time.time()

    try:
        while True:
            # Stop after DURATION_SEC of *wall-clock* time
            if (time.time() - t_capture_start) > DURATION_SEC:
                break

            try:
                raw = ser.readline()
            except SerialException as e:
                print("Serial read error during capture:", e)
                break

            if not raw:
                # timeout, no line
                continue

            line = raw.decode("utf-8", errors="ignore").strip()
            # You can uncomment this to debug:
            # print("DATA:", line)

            parts = line.split(",")
            if len(parts) != 5:
                # Not a data line
                continue

            try:
                timestamp_us = int(parts[0])
                sensor_id = int(parts[1])
                x_raw = int(parts[2])
                y_raw = int(parts[3])
                z_raw = int(parts[4])
            except ValueError:
                # malformed line
                continue

            if sensor_id != SENSOR_ID:
                continue

            if t_start is None:
                t_start = timestamp_us
            t = (timestamp_us - t_start) / 1_000_000.0  # seconds

            x_g = x_raw * LSB_TO_G
            y_g = y_raw * LSB_TO_G
            z_g = z_raw * LSB_TO_G

            t_list.append(t)
            xg_list.append(x_g)
            yg_list.append(y_g)
            zg_list.append(z_g)

    except KeyboardInterrupt:
        print("Capture interrupted by user.")

    ser.close()
    print(f"Captured {len(t_list)} samples.")

    if not t_list:
        print("No data captured; check that data lines are coming from the Pico.")
        return

    # -------------------
    # Plotting
    # -------------------
    plt.figure(figsize=(10, 6))
    plt.plot(t_list, xg_list, label="Ax (g)")
    plt.plot(t_list, yg_list, label="Ay (g)")
    plt.plot(t_list, zg_list, label="Az (g)")
    plt.xlabel("Time (s)")
    plt.ylabel("Acceleration (g)")
    plt.title(f"ADXL372 Acceleration vs Time (sensor {SENSOR_ID})")
    plt.legend()
    plt.grid(True)
    plt.tight_layout()
    plt.show()


if __name__ == "__main__":
    main()
