// ShakerTableMonitor.c
// =====================================================================
// PURPOSE:
//   Initialize 5 ADXL372 accelerometers on a shared SPI bus, read
//   XYZ acceleration data from each sensor's FIFO, and write timestamped
//   CSV records to a MicroSD card.  All post-processing (PSD, RMS,
//   comparison with ANSYS) is done in MATLAB after the test.
//
// HARDWARE:
//   - Raspberry Pi Pico (RP2040)
//   - 5x ADXL372 high-g MEMS accelerometers (shared SPI0 bus)
//   - MicroSD card module (SPI1, separate bus)
//   - Momentary pushbutton for start/stop
//
// CSV FORMAT (one line per XYZ sample):
//   timestamp_us, sensor_id, x_raw, y_raw, z_raw
//
//   - timestamp_us : microseconds since the start of the current run
//   - sensor_id    : 0..4
//   - x/y/z_raw    : 12-bit signed codes (multiply by 0.1 in MATLAB to get g)
//
// TEST RUNS:
//   NUM_TEST_RUNS sets how many runs to perform.  Each run produces
//   one file (run_001.csv, run_002.csv, ...).  Press the button to
//   start a run, press again (or wait for MAX_RUN_SECONDS) to stop.
// =====================================================================

#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#include "pico/stdlib.h"
#include "pico/types.h"
#include "hardware/spi.h"
#include "hardware/gpio.h"

// FatFs headers (add ff.c, diskio.c, and your SD SPI driver to CMake).
// Recommended: carlk3 "no-OS-FatFS-SD-SDIO-SPI-RPi-Pico" library.
#include "ff.h"
#include "f_util.h"
#include "hw_config.h"


// =====================================================================
//  PIN ASSIGNMENTS  –  CHANGE THESE TO MATCH YOUR WIRING
// =====================================================================

// --- Accelerometer SPI bus (SPI0) ---
static uint PIN_ACCEL_SCK  = 2;
static uint PIN_ACCEL_MOSI = 3;
static uint PIN_ACCEL_MISO = 4;

// --- Per-sensor chip-select and interrupt pins ---
// Index 0..4 corresponds to sensor 0..4.
static uint SENSOR_CS_PINS[5]   = {  5,  7,  9, 11, 13 };
static uint SENSOR_INT1_PINS[5] = {  6,  8, 10, 12, 14 };

// --- SD card SPI bus (SPI1) ---
// These are configured in hw_config.c for FatFs; listed here for reference.
// static uint PIN_SD_SCK  = 18;
// static uint PIN_SD_MOSI = 19;
// static uint PIN_SD_MISO = 16;
// static uint PIN_SD_CS   = 17;

// --- UI ---
static uint PIN_START_BTN  = 15;    // Momentary pushbutton (active-low)
static uint PIN_STATUS_LED = 25;    // Pico onboard LED


// =====================================================================
//  TEST PARAMETERS  –  CHANGE THESE PER YOUR TEST MATRIX
// =====================================================================

#define NUM_TEST_RUNS       3       // Number of runs this session
#define MAX_RUN_SECONDS     60      // Auto-stop safety cap (0 = no limit)
#define NUM_SENSORS         5       // Number of ADXL372 accelerometers


// =====================================================================
//  ADXL372 CONSTANTS
// =====================================================================

#define ACCEL_SPI_PORT      spi0
#define ACCEL_SPI_BAUD_HZ   8000000     // 8 MHz (ADXL372 max = 10 MHz)

// Register addresses
#define REG_DEVID_AD        0x00
#define REG_DEVID_MST       0x01
#define REG_PARTID          0x02
#define REG_STATUS          0x04
#define REG_FIFO_ENTRIES    0x07
#define REG_FIFO_SAMPLES    0x39
#define REG_FIFO_CTL        0x3A
#define REG_INT1_MAP        0x3B
#define REG_TIMING          0x3D
#define REG_MEASURE         0x3E
#define REG_POWER_CTL       0x3F
#define REG_RESET           0x41
#define REG_FIFO_DATA       0x42

// Expected silicon IDs
#define DEVID_AD_EXPECTED   0xAD
#define DEVID_MST_EXPECTED  0x1D
#define PARTID_EXPECTED     0xFA

// FIFO watermark in axis-samples (240 = 80 XYZ sets ≈ 12.5 ms at 6400 Hz)
#define FIFO_WATERMARK      240


// =====================================================================
//  SENSOR STATE
// =====================================================================

typedef struct {
    uint cs_pin;
    uint int1_pin;
    volatile bool fifo_irq;     // Set true by GPIO ISR
} sensor_t;

static sensor_t sensors[NUM_SENSORS];


// =====================================================================
//  SD WRITE BUFFER
//  Batches CSV text in RAM to avoid an SD write per sample line.
// =====================================================================

#define SD_BUF_SIZE     (16 * 1024)

static char   sd_buf[SD_BUF_SIZE];
static size_t sd_buf_pos  = 0;
static FIL    sd_file;
static bool   sd_file_open = false;

static void sd_flush(void) {
    if (!sd_file_open || sd_buf_pos == 0) return;
    UINT bw = 0;
    FRESULT fr = f_write(&sd_file, sd_buf, (UINT)sd_buf_pos, &bw);
    if (fr != FR_OK) {
        printf("[SD ERROR] write failed, code %d\n", (int)fr);
    }
    sd_buf_pos = 0;
}

static void sd_append(const char *data, size_t len) {
    if (sd_buf_pos + len >= SD_BUF_SIZE) {
        sd_flush();
    }
    memcpy(&sd_buf[sd_buf_pos], data, len);
    sd_buf_pos += len;
}


// =====================================================================
//  SPI HELPERS
// =====================================================================

static inline void spi_write_reg(uint cs, uint8_t reg, uint8_t val) {
    uint8_t cmd = (uint8_t)((reg << 1) & 0xFE);
    gpio_put(cs, 0);
    spi_write_blocking(ACCEL_SPI_PORT, &cmd, 1);
    spi_write_blocking(ACCEL_SPI_PORT, &val, 1);
    gpio_put(cs, 1);
}

static inline uint8_t spi_read_reg(uint cs, uint8_t reg) {
    uint8_t cmd = (uint8_t)((reg << 1) | 0x01);
    uint8_t val = 0;
    gpio_put(cs, 0);
    spi_write_blocking(ACCEL_SPI_PORT, &cmd, 1);
    spi_read_blocking(ACCEL_SPI_PORT, 0x00, &val, 1);
    gpio_put(cs, 1);
    return val;
}

static inline void spi_read_burst(uint cs, uint8_t reg,
                                   uint8_t *buf, size_t len) {
    uint8_t cmd = (uint8_t)((reg << 1) | 0x01);
    gpio_put(cs, 0);
    spi_write_blocking(ACCEL_SPI_PORT, &cmd, 1);
    spi_read_blocking(ACCEL_SPI_PORT, 0x00, buf, len);
    gpio_put(cs, 1);
}


// =====================================================================
//  ADXL372 INIT / STANDBY
// =====================================================================

static bool adxl372_init(sensor_t *s) {
    uint cs = s->cs_pin;

    // Soft-reset
    spi_write_reg(cs, REG_RESET, 0x52);
    sleep_ms(5);

    // Verify silicon IDs
    if (spi_read_reg(cs, REG_DEVID_AD)  != DEVID_AD_EXPECTED  ||
        spi_read_reg(cs, REG_DEVID_MST) != DEVID_MST_EXPECTED ||
        spi_read_reg(cs, REG_PARTID)    != PARTID_EXPECTED) {
        return false;
    }

    // Standby while configuring
    spi_write_reg(cs, REG_POWER_CTL, 0x00);

    // ODR = 6400 Hz  (TIMING bits [7:5] = 100)
    spi_write_reg(cs, REG_TIMING, (uint8_t)(4u << 5));

    // BW = 3200 Hz, LOW_NOISE on
    spi_write_reg(cs, REG_MEASURE, (uint8_t)((1u << 3) | 4u));

    // FIFO watermark
    spi_write_reg(cs, REG_FIFO_SAMPLES, FIFO_WATERMARK);

    // FIFO: XYZ format, stream mode
    spi_write_reg(cs, REG_FIFO_CTL, (uint8_t)(1u << 1));

    // INT1 on FIFO_FULL and FIFO_OVR
    spi_write_reg(cs, REG_INT1_MAP, (uint8_t)((1u << 3) | (1u << 2)));

    // Clear pending interrupts
    (void)spi_read_reg(cs, REG_STATUS);

    // Full BW measurement mode, fast filter settle
    spi_write_reg(cs, REG_POWER_CTL, (uint8_t)((1u << 4) | 0x03));
    sleep_ms(20);

    return true;
}

static void adxl372_standby(sensor_t *s) {
    spi_write_reg(s->cs_pin, REG_POWER_CTL, 0x00);
}


// =====================================================================
//  GPIO INTERRUPT CALLBACK
// =====================================================================

static void gpio_int_callback(uint gpio, uint32_t events) {
    (void)events;
    for (int i = 0; i < NUM_SENSORS; i++) {
        if (gpio == sensors[i].int1_pin) {
            sensors[i].fifo_irq = true;
        }
    }
}


// =====================================================================
//  FIFO READ → SD BUFFER
//  Reads one sensor's FIFO, decodes raw XYZ, appends CSV lines.
// =====================================================================

static void service_fifo(sensor_t *s, int id, uint32_t t0) {
    uint cs = s->cs_pin;

    uint16_t entries = spi_read_reg(cs, REG_FIFO_ENTRIES);
    if (entries == 0) return;

    uint16_t sets = entries / 3;
    if (sets == 0) return;

    // Leave 1 set in FIFO for alignment; cap to buffer size
    if (sets > 169) sets = 169;
    if (sets > 1) sets -= 1; else return;

    uint16_t words = sets * 3;
    uint16_t bytes = words * 2;

    uint8_t buf[1024];
    if (bytes > sizeof(buf)) {
        bytes = sizeof(buf);
        words = bytes / 2;
    }

    // Burst-read FIFO data
    spi_read_burst(cs, REG_FIFO_DATA, buf, bytes);

    // Timestamp relative to run start
    uint32_t now = time_us_32() - t0;

    // Decode and buffer CSV lines
    int axis = 0;
    int16_t x = 0, y = 0, z = 0;
    char line[64];

    for (uint16_t i = 0; i < words; i++) {
        uint16_t word = (uint16_t)(((uint16_t)buf[2*i] << 8) | buf[2*i+1]);

        // Bit 0 = series-start flag → re-align to X axis
        if (word & 0x0001u) axis = 0;

        // Acceleration: bits [15:4], twos complement, left-justified
        int16_t val = (int16_t)word;
        val >>= 4;

        if      (axis == 0) x = val;
        else if (axis == 1) y = val;
        else if (axis == 2) {
            z = val;
            int len = snprintf(line, sizeof(line),
                               "%lu,%d,%d,%d,%d\n",
                               (unsigned long)now, id,
                               (int)x, (int)y, (int)z);
            if (len > 0) sd_append(line, (size_t)len);
        }

        axis = (axis + 1) % 3;
    }

    // Clear interrupt flags
    (void)spi_read_reg(cs, REG_STATUS);
}


// =====================================================================
//  BUTTON / LED HELPERS
// =====================================================================

static bool button_pressed(void) {
    if (gpio_get(PIN_START_BTN) == 0) {
        sleep_ms(50);
        return (gpio_get(PIN_START_BTN) == 0);
    }
    return false;
}

static void wait_button_release(void) {
    while (gpio_get(PIN_START_BTN) == 0) sleep_ms(10);
    sleep_ms(50);
}

static void led_blink(uint32_t interval_us) {
    static uint32_t last = 0;
    uint32_t now = time_us_32();
    if (now - last > interval_us) {
        gpio_put(PIN_STATUS_LED, !gpio_get(PIN_STATUS_LED));
        last = now;
    }
}


// =====================================================================
//  MAIN
// =====================================================================

int main(void) {
    stdio_init_all();
    sleep_ms(2000);
    while (!stdio_usb_connected()) sleep_ms(100);

    printf("=== ShakerTableMonitor ===\n");
    printf("Sensors: %d | Runs: %d | Timeout: %d s\n",
           NUM_SENSORS, NUM_TEST_RUNS, MAX_RUN_SECONDS);

    // ---- LED ----
    gpio_init(PIN_STATUS_LED);
    gpio_set_dir(PIN_STATUS_LED, GPIO_OUT);

    // ---- Button (active-low, internal pull-up) ----
    gpio_init(PIN_START_BTN);
    gpio_set_dir(PIN_START_BTN, GPIO_IN);
    gpio_pull_up(PIN_START_BTN);

    // ---- SPI0 for accelerometers ----
    spi_init(ACCEL_SPI_PORT, ACCEL_SPI_BAUD_HZ);
    gpio_set_function(PIN_ACCEL_SCK,  GPIO_FUNC_SPI);
    gpio_set_function(PIN_ACCEL_MOSI, GPIO_FUNC_SPI);
    gpio_set_function(PIN_ACCEL_MISO, GPIO_FUNC_SPI);

    // ---- Build sensor structs from pin arrays ----
    for (int i = 0; i < NUM_SENSORS; i++) {
        sensors[i].cs_pin    = SENSOR_CS_PINS[i];
        sensors[i].int1_pin  = SENSOR_INT1_PINS[i];
        sensors[i].fifo_irq  = false;

        gpio_init(sensors[i].cs_pin);
        gpio_set_dir(sensors[i].cs_pin, GPIO_OUT);
        gpio_put(sensors[i].cs_pin, 1);            // CS idle high

        gpio_init(sensors[i].int1_pin);
        gpio_set_dir(sensors[i].int1_pin, GPIO_IN);
        gpio_pull_down(sensors[i].int1_pin);
    }

    // ---- GPIO interrupts (one callback for all sensors) ----
    gpio_set_irq_enabled_with_callback(
        sensors[0].int1_pin, GPIO_IRQ_EDGE_RISE, true, &gpio_int_callback);
    for (int i = 1; i < NUM_SENSORS; i++) {
        gpio_set_irq_enabled(sensors[i].int1_pin, GPIO_IRQ_EDGE_RISE, true);
    }

    // ---- Init sensors, then standby until run starts ----
    for (int i = 0; i < NUM_SENSORS; i++) {
        bool ok = adxl372_init(&sensors[i]);
        printf("Sensor %d: %s\n", i, ok ? "OK" : "FAILED");
        adxl372_standby(&sensors[i]);
    }

    // ---- Mount SD card ----
    FATFS fs;
    FRESULT fr = f_mount(&fs, "", 1);
    if (fr != FR_OK) {
        printf("[FATAL] SD mount failed (code %d)\n", (int)fr);
        while (true) tight_loop_contents();
    }
    printf("SD card mounted.\n");

    // ================================================================
    //  RUN LOOP
    // ================================================================
    for (int run = 1; run <= NUM_TEST_RUNS; run++) {

        // ---- Wait for button press ----
        printf("\n-- Run %d/%d: press button to START --\n", run, NUM_TEST_RUNS);
        while (!button_pressed()) {
            led_blink(150000);
            tight_loop_contents();
        }
        wait_button_release();

        // ---- Open CSV file ----
        char fname[32];
        snprintf(fname, sizeof(fname), "run_%03d.csv", run);
        fr = f_open(&sd_file, fname, FA_WRITE | FA_CREATE_ALWAYS);
        if (fr != FR_OK) {
            printf("[ERROR] Can't create %s (code %d)\n", fname, (int)fr);
            continue;
        }
        sd_file_open = true;
        sd_buf_pos   = 0;

        const char *hdr = "timestamp_us,sensor_id,x_raw,y_raw,z_raw\n";
        sd_append(hdr, strlen(hdr));

        // ---- Wake sensors ----
        for (int i = 0; i < NUM_SENSORS; i++) {
            adxl372_init(&sensors[i]);
            sensors[i].fifo_irq = false;
        }

        uint32_t t0      = time_us_32();
        bool     running  = true;

        printf("[RUN %d] Recording to %s ...\n", run, fname);

        // ---- Acquisition loop ----
        while (running) {
            for (int i = 0; i < NUM_SENSORS; i++) {
                if (sensors[i].fifo_irq) {
                    sensors[i].fifo_irq = false;
                    service_fifo(&sensors[i], i, t0);
                }
            }

            if (button_pressed()) {
                wait_button_release();
                running = false;
            }

            if (MAX_RUN_SECONDS > 0 &&
                (time_us_32() - t0) > (uint32_t)MAX_RUN_SECONDS * 1000000u) {
                running = false;
            }

            led_blink(500000);
            tight_loop_contents();
        }

        // ---- Close run ----
        sd_flush();
        f_sync(&sd_file);
        f_close(&sd_file);
        sd_file_open = false;

        for (int i = 0; i < NUM_SENSORS; i++) {
            adxl372_standby(&sensors[i]);
        }

        uint32_t dur_ms = (time_us_32() - t0) / 1000;
        printf("[RUN %d] Done. %lu ms, saved %s\n",
               run, (unsigned long)dur_ms, fname);
    }

    // ---- Session complete ----
    f_unmount("");
    printf("\nAll runs complete. Safe to remove SD card.\n");

    while (true) {
        gpio_put(PIN_STATUS_LED, 1); sleep_ms(1000);
        gpio_put(PIN_STATUS_LED, 0); sleep_ms(1000);
    }

    return 0;
}
