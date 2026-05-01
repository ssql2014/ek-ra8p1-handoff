/*
 * display_smoke.c — minimal C-side GLCDC smoke test for EK_RA8P1.
 *
 * Goal: open the GLCDC instance generated as g_plcd_display, start the
 * display, and paint a solid color (or simple pattern) into the SDRAM
 * framebuffer so the panel shows visible pixels.  This is the FIRST
 * milestone per /Users/alex/ek-ra8p1-handoff/originals/ek-ra8p1-display-
 * integration-plan.md.  No Python API yet.
 *
 * Drop this file at:
 *   ports/renesas-ra/boards/EK_RA8P1/display_smoke.c
 * and add to boards/EK_RA8P1/mpconfigboard.mk:
 *   SRC_C += boards/EK_RA8P1/display_smoke.c
 *   USE_FSP_GLCDC = 1
 *   USE_FSP_DAVE2D = 1
 *
 * Wire into ports/renesas-ra/main.c in the early-init region (before
 * REPL):
 *   #if MICROPY_RA8P1_BRINGUP_DISPLAY_SMOKE_TEST
 *   extern void ra8p1_display_smoke(void);
 *   ra8p1_display_smoke();
 *   #endif
 *
 * Add to boards/EK_RA8P1/mpconfigboard.h:
 *   #define MICROPY_RA8P1_BRINGUP_DISPLAY_SMOKE_TEST (1)
 *
 * Assumed generated symbols (post-FSP-codegen on staged configuration.xml):
 *   g_plcd_display      — display_instance_t const (defined in hal_data.c)
 *     ↳ p_ctrl, p_cfg
 *   g_plcd_display.p_cfg->input[0].p_base / hsize / vsize / format
 *
 * Per ek-ra8p1-vcom-handoff.md, the staged config gives:
 *   Layer 1: fb_background, 768x450, RGB565, in .sdram_noinit
 *   Layer 2: fb_foreground, 1024x600, ARGB4444, 2 buffers, in .sdram_noinit
 * BSP_CFG_SDRAM_ENABLED=1 → SDRAM is already up at BSP_WARM_START_POST_C.
 */

#include "py/mpconfig.h"

#if MICROPY_RA8P1_BRINGUP_DISPLAY_SMOKE_TEST

#include "hal_data.h"
#include "r_glcdc_api.h"

/* RGB565 helpers */
#define RGB565(r, g, b) (uint16_t)((((r) & 0xF8) << 8) | (((g) & 0xFC) << 3) | (((b) & 0xF8) >> 3))
#define COLOR_RED       RGB565(0xFF, 0x00, 0x00)
#define COLOR_GREEN     RGB565(0x00, 0xFF, 0x00)
#define COLOR_BLUE      RGB565(0x00, 0x00, 0xFF)
#define COLOR_BLACK     RGB565(0x00, 0x00, 0x00)
#define COLOR_WHITE     RGB565(0xFF, 0xFF, 0xFF)
#define COLOR_YELLOW    RGB565(0xFF, 0xFF, 0x00)
#define COLOR_MAGENTA   RGB565(0xFF, 0x00, 0xFF)
#define COLOR_CYAN      RGB565(0x00, 0xFF, 0xFF)

/* Backlight enable pin per board doc (P514 DISP_BLEN, active high). */
#ifndef DISPLAY_SMOKE_BLEN_PORT
#define DISPLAY_SMOKE_BLEN_PORT (BSP_IO_PORT_05_PIN_14)
#endif

static void fill_layer_rgb565(uint16_t *fb, uint16_t hsize, uint16_t vsize, uint16_t color) {
    uint32_t n = (uint32_t)hsize * (uint32_t)vsize;
    for (uint32_t i = 0; i < n; i++) {
        fb[i] = color;
    }
}

static void color_bands_rgb565(uint16_t *fb, uint16_t hsize, uint16_t vsize) {
    static const uint16_t bands[8] = {
        COLOR_RED, COLOR_GREEN, COLOR_BLUE, COLOR_BLACK,
        COLOR_WHITE, COLOR_YELLOW, COLOR_MAGENTA, COLOR_CYAN
    };
    uint16_t band_height = vsize / 8;
    for (uint16_t y = 0; y < vsize; y++) {
        uint16_t band = (band_height > 0) ? (y / band_height) : 0;
        if (band > 7) band = 7;
        uint16_t color = bands[band];
        uint16_t *row = fb + (uint32_t)y * hsize;
        for (uint16_t x = 0; x < hsize; x++) {
            row[x] = color;
        }
    }
}

void ra8p1_display_smoke(void) {
    fsp_err_t err;

    /* Backlight off during programming, on after first frame. */
    R_IOPORT_PinDirectionSet(&g_ioport_ctrl, DISPLAY_SMOKE_BLEN_PORT,
                             BSP_IO_DIRECTION_OUTPUT);
    R_IOPORT_PinWrite(&g_ioport_ctrl, DISPLAY_SMOKE_BLEN_PORT, BSP_IO_LEVEL_LOW);

    /* Open GLCDC.  Symbol comes from generated hal_data.c. */
    err = R_GLCDC_Open(g_plcd_display.p_ctrl, g_plcd_display.p_cfg);
    if (FSP_SUCCESS != err) {
        return;
    }

    /* Compute framebuffer for input layer 0 (background). */
    const display_cfg_t *cfg = g_plcd_display.p_cfg;
    uint16_t hsize = cfg->input[0].hsize;
    uint16_t vsize = cfg->input[0].vsize;
    uint16_t *fb_layer0 = (uint16_t *)cfg->input[0].p_base;

    /* Paint color bands so we can see scan order and field state. */
    color_bands_rgb565(fb_layer0, hsize, vsize);

    /* Layer 1 (foreground) — clear to fully transparent ARGB4444 if present. */
    if (cfg->input[1].p_base != NULL) {
        uint16_t hf = cfg->input[1].hsize;
        uint16_t vf = cfg->input[1].vsize;
        uint16_t *fb_layer1 = (uint16_t *)cfg->input[1].p_base;
        uint32_t n = (uint32_t)hf * (uint32_t)vf;
        for (uint32_t i = 0; i < n; i++) {
            fb_layer1[i] = 0x0000;  /* alpha=0, fully transparent */
        }
    }

    /* Start scanning. */
    err = R_GLCDC_Start(g_plcd_display.p_ctrl);
    if (FSP_SUCCESS != err) {
        return;
    }

    /* Allow a few frames to settle before turning on backlight (eliminates
     * scrambled-flash on power-up).  At 60Hz, 5 frames = ~83ms. */
    R_BSP_SoftwareDelay(100, BSP_DELAY_UNITS_MILLISECONDS);

    /* Backlight on. */
    R_IOPORT_PinWrite(&g_ioport_ctrl, DISPLAY_SMOKE_BLEN_PORT, BSP_IO_LEVEL_HIGH);
}

#endif /* MICROPY_RA8P1_BRINGUP_DISPLAY_SMOKE_TEST */
