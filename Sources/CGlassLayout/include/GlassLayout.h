#ifndef GLASS_LAYOUT_H
#define GLASS_LAYOUT_H

// Pure screen geometry for GlassDesk: where the top bar goes, how big widgets are on a
// given screen and where they sit. No AppKit in here, so it can be tested on its own
// (see Sources/GlassLayoutTests).
//
// Every rectangle is in AppKit screen coordinates: the origin is the bottom-left corner
// and y grows upwards, the same as NSScreen.frame.

#ifdef __cplusplus
extern "C" {
#endif

typedef struct GLSize {
    double width;
    double height;
} GLSize;

typedef struct GLRect {
    double x;
    double y;
    double width;
    double height;
} GLRect;

// MARK: - Top bar

typedef struct GLBarLayout {
    // 0 when the menu bar is hidden on this screen (auto-hide), so no glass should show.
    int visible;
    // The glass window's frame: the strip of the screen the menu bar occupies.
    GLRect bar;
    // The capsule inside that window, in the window's own coordinates.
    GLRect capsule;
} GLBarLayout;

// The menu bar strip is whatever the screen's visible frame gives up at the top. When it
// is shorter than minBarHeight the menu bar is hidden and the layout is not visible.
GLBarLayout gl_menu_bar_layout(GLRect screenFrame,
                               GLRect visibleFrame,
                               double edgeInset,
                               double verticalInset,
                               double minBarHeight);

// 1 when a window lies along the top edge of a screen and spans its width, to within
// `tolerance`: the shape of the menu bar strip. macOS keeps an invisible "menu bar agent"
// window of exactly this shape on a display whose menu bar is hidden (a full-screen Space,
// or auto-hide), which is how we know the glass must not show there. Both rectangles must
// be in the same coordinate space and orientation.
int gl_rect_is_top_strip(GLRect window, GLRect screen, double tolerance);

// MARK: - Widgets

typedef struct GLScaleRules {
    // The screen widgets were designed on, in points.
    GLSize baselineScreen;
    // How far the automatic scale may shrink or grow.
    double smallestAutomatic;
    double largestAutomatic;
    // The Widget Size setting, 1 meaning automatic.
    double userMultiplier;
    // Transparent margin around each card, in unscaled points, for the glass shadow.
    double cardMargin;
    // Space left between a card and the edge of the usable area.
    double edgeGap;
} GLScaleRules;

// How much to draw a widget on a screen. The automatic factor follows the screen size
// (the smaller of the width and height ratios, so ultrawide monitors don't over-scale),
// the user multiplier goes on top, and the result is capped so the whole card still fits
// inside `usableArea`, so a widget can never be bigger than the screen it is on.
// `naturalSize` is the widget's unscaled size including its margin.
double gl_widget_scale(const GLScaleRules *rules,
                       GLSize screenSize,
                       GLSize naturalSize,
                       GLSize usableArea);

// Moves a panel so its card (the panel minus `margin` on every side) lies fully inside
// `area`. A card larger than the area is pinned to the area's top-left corner.
GLRect gl_clamp_panel(GLRect panel, double margin, GLRect area);

// A card's centre as a fraction of a screen's frame. Saved instead of raw coordinates so
// the widget lands in the same relative spot on a screen of another size.
typedef struct GLPlacement {
    double fractionX;
    double fractionY;
} GLPlacement;

GLPlacement gl_placement_from_card(GLRect card, GLRect screenFrame);
GLRect gl_card_from_placement(GLPlacement placement, GLSize cardSize, GLRect screenFrame);

// Stacks cards down the right edge of `area`, starting a new column to the left whenever
// a column is full. `cards` are sizes, `gap` is the space between neighbouring cards and
// `outCards` receives one rectangle per card.
void gl_stack_cards(GLRect area,
                    const GLSize *cards,
                    int count,
                    double gap,
                    GLRect *outCards);

#ifdef __cplusplus
}
#endif

#endif
