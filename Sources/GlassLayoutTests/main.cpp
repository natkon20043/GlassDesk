// Checks for the screen geometry in CGlassLayout. Run with: swift run GlassLayoutTests

#include "GlassLayout.h"

#include <cmath>
#include <cstdio>

static int failures = 0;

static void check(bool condition, const char *what) {
    if (condition) {
        return;
    }
    std::printf("FAIL: %s\n", what);
    failures++;
}

static bool near(double a, double b) {
    return std::fabs(a - b) < 0.001;
}

static GLScaleRules defaultRules() {
    GLScaleRules rules = {};
    rules.baselineScreen = GLSize{1710, 1107};
    rules.smallestAutomatic = 0.85;
    rules.largestAutomatic = 2.5;
    rules.userMultiplier = 1.0;
    rules.cardMargin = 16;
    rules.edgeGap = 12;
    return rules;
}

static void testMenuBar() {
    GLRect screen = {0, 0, 1440, 932};

    GLRect withBar = {0, 105, 1440, 798};  // 29 pt menu bar, 105 pt Dock
    GLBarLayout shown = gl_menu_bar_layout(screen, withBar, 8, 2, 18);
    check(shown.visible == 1, "bar visible when the menu bar takes space");
    check(near(shown.bar.height, 29), "bar height is the menu bar height");
    check(near(shown.bar.y, 903), "bar sits at the top of the screen");
    check(near(shown.capsule.x, 8) && near(shown.capsule.width, 1424), "capsule stops short of the edges");
    check(near(shown.capsule.height, 25), "capsule leaves the vertical inset");

    GLRect fullScreenApp = {0, 0, 1440, 932};  // nothing reserved at the top
    check(gl_menu_bar_layout(screen, fullScreenApp, 8, 2, 18).visible == 0, "bar hidden when the menu bar is hidden");

    GLRect secondScreen = {1440, -200, 2560, 1440};
    GLRect secondVisible = {1440, -200, 2560, 1412};  // 28 pt bar
    GLBarLayout other = gl_menu_bar_layout(secondScreen, secondVisible, 8, 2, 18);
    check(near(other.bar.x, 1440) && near(other.bar.y, 1212), "bar follows a screen that is offset from the origin");
}

static void testTopStrip() {
    GLRect screen = {0, 0, 1440, 932};
    check(gl_rect_is_top_strip(GLRect{0, 903, 1440, 29}, screen, 1) == 1, "menu bar agent strip is recognised");
    check(gl_rect_is_top_strip(GLRect{0, 0, 1440, 903}, screen, 1) == 0, "a window below the menu bar is not the strip");
    check(gl_rect_is_top_strip(GLRect{0, 0, 1440, 932}, screen, 1) == 0, "a full-screen sized window is not the strip");
    check(gl_rect_is_top_strip(GLRect{300, 903, 400, 29}, screen, 1) == 0, "a short strip is not the strip");

    GLRect second = {1440, -200, 2560, 1440};
    check(gl_rect_is_top_strip(GLRect{1440, 1212, 2560, 28}, second, 1) == 1, "strip on an offset display is recognised");
    check(gl_rect_is_top_strip(GLRect{1440, 1212, 2560, 28}, screen, 1) == 0, "a strip on another display does not match");
}

static void testScale() {
    GLScaleRules rules = defaultRules();
    GLSize natural = {352, 236};  // card 320 x 204 plus margins

    double laptop = gl_widget_scale(&rules, GLSize{1710, 1107}, natural, GLSize{1710, 1000});
    check(near(laptop, 1.0), "baseline screen draws widgets at their designed size");

    double big = gl_widget_scale(&rules, GLSize{3420, 2214}, natural, GLSize{3420, 2100});
    check(near(big, 2.0), "a screen twice as large doubles the widgets");

    double ultrawide = gl_widget_scale(&rules, GLSize{3440, 1440}, natural, GLSize{3440, 1400});
    check(near(ultrawide, 1440.0 / 1107.0), "ultrawide screens scale by height");

    double small = gl_widget_scale(&rules, GLSize{800, 600}, natural, GLSize{800, 560});
    check(near(small, 0.85), "small screens never shrink widgets below the minimum");

    // A tall widget on a short screen is capped so it fits instead of being cut off.
    GLSize tall = {352, 700};
    double capped = gl_widget_scale(&rules, GLSize{1710, 1107}, tall, GLSize{1710, 400});
    double cardHeight = 700 - 32;
    check(near(capped, (400 - 24) / cardHeight), "widget taller than the screen is shrunk to fit");
    check(capped * cardHeight <= 400 - 24 + 0.001, "capped widget fits inside the usable area");

    rules.userMultiplier = 1.5;
    double bigger = gl_widget_scale(&rules, GLSize{1710, 1107}, natural, GLSize{1710, 1000});
    check(near(bigger, 1.5), "Widget Size multiplies the automatic scale");
}

static void testClamp() {
    GLRect area = {0, 100, 1440, 800};
    double margin = 16;

    GLRect inside = {200, 300, 352, 236};
    GLRect same = gl_clamp_panel(inside, margin, area);
    check(near(same.x, 200) && near(same.y, 300), "a panel that fits is left alone");

    GLRect offRight = {1300, 300, 352, 236};
    GLRect fixedRight = gl_clamp_panel(offRight, margin, area);
    check(near(fixedRight.x + margin + (352 - 32), 1440), "a card hanging off the right edge is pulled back");

    GLRect belowDock = {200, 40, 352, 236};
    GLRect fixedBottom = gl_clamp_panel(belowDock, margin, area);
    check(near(fixedBottom.y + margin, 100), "a card below the area is lifted onto it");

    GLRect huge = {-500, -500, 4000, 3000};
    GLRect pinned = gl_clamp_panel(huge, margin, area);
    check(near(pinned.x + margin, 0), "an oversized card is pinned to the left");
    check(near(pinned.y + margin + (3000 - 32), 900), "an oversized card is pinned to the top");
}

static void testPlacement() {
    GLRect laptop = {0, 0, 1440, 932};
    GLRect card = {1064, 600, 320, 204};
    GLPlacement placement = gl_placement_from_card(card, laptop);

    GLRect sameScreen = gl_card_from_placement(placement, GLSize{320, 204}, laptop);
    check(near(sameScreen.x, card.x) && near(sameScreen.y, card.y), "placement round-trips on the same screen");

    GLRect monitor = {0, 0, 2880, 1864};
    GLRect scaled = gl_card_from_placement(placement, GLSize{640, 408}, monitor);
    double centreX = scaled.x + scaled.width / 2;
    check(near(centreX / monitor.width, placement.fractionX), "placement keeps its relative spot on a larger screen");
}

static void testStack() {
    GLRect area = {0, 0, 1000, 500};
    GLSize cards[3] = {{300, 200}, {300, 200}, {300, 200}};
    GLRect placed[3] = {};
    gl_stack_cards(area, cards, 3, 12, placed);

    check(near(placed[0].x + placed[0].width, 1000), "first card hugs the right edge");
    check(near(placed[0].y + placed[0].height, 500), "first card starts at the top");
    check(near(placed[1].y + placed[1].height, 500 - 212), "second card sits below the first with the gap");
    check(placed[2].x + placed[2].width < 1000, "third card does not fit and starts a new column");
    check(near(placed[2].x + placed[2].width, 1000 - 300 - 12), "new column is one card width plus gap to the left");
    check(near(placed[2].y + placed[2].height, 500), "new column starts at the top");
}

int main() {
    testMenuBar();
    testTopStrip();
    testScale();
    testClamp();
    testPlacement();
    testStack();

    if (failures == 0) {
        std::printf("All GlassLayout checks passed.\n");
        return 0;
    }
    std::printf("%d check(s) failed.\n", failures);
    return 1;
}
