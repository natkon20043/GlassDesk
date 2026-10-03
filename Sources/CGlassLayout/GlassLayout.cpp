#include "GlassLayout.h"

#include <algorithm>
#include <cmath>

namespace {

double largerOf(double a, double b) {
    if (a > b) {
        return a;
    }
    return b;
}

double smallerOf(double a, double b) {
    if (a < b) {
        return a;
    }
    return b;
}

double clampValue(double value, double low, double high) {
    return smallerOf(largerOf(value, low), high);
}

double maxX(const GLRect &rect) { return rect.x + rect.width; }
double maxY(const GLRect &rect) { return rect.y + rect.height; }

}  // namespace

// MARK: - Top bar

GLBarLayout gl_menu_bar_layout(GLRect screenFrame,
                               GLRect visibleFrame,
                               double edgeInset,
                               double verticalInset,
                               double minBarHeight) {
    GLBarLayout layout = {};

    // The menu bar is the gap between the top of the screen and the top of the visible
    // frame. Zero (or a sliver) means the menu bar is auto-hidden or not shown here.
    double barHeight = maxY(screenFrame) - maxY(visibleFrame);
    if (barHeight < minBarHeight) {
        layout.visible = 0;
        return layout;
    }

    layout.visible = 1;
    layout.bar = GLRect{screenFrame.x, maxY(screenFrame) - barHeight, screenFrame.width, barHeight};
    layout.capsule = GLRect{edgeInset,
                            verticalInset,
                            screenFrame.width - edgeInset * 2,
                            barHeight - verticalInset * 2};
    return layout;
}

int gl_rect_is_top_strip(GLRect window, GLRect screen, double tolerance) {
    bool spansWidth = window.width >= screen.width - tolerance;
    bool startsAtLeft = std::fabs(window.x - screen.x) <= tolerance;
    bool touchesTop = std::fabs(maxY(window) - maxY(screen)) <= tolerance;
    bool isStrip = window.height > 0 && window.height < screen.height / 2;

    if (spansWidth && startsAtLeft && touchesTop && isStrip) {
        return 1;
    }
    return 0;
}

// MARK: - Widgets

double gl_widget_scale(const GLScaleRules *rules,
                       GLSize screenSize,
                       GLSize naturalSize,
                       GLSize usableArea) {
    double widthRatio = screenSize.width / rules->baselineScreen.width;
    double heightRatio = screenSize.height / rules->baselineScreen.height;
    double automatic = smallerOf(widthRatio, heightRatio);
    double limitedAutomatic = clampValue(automatic, rules->smallestAutomatic, rules->largestAutomatic);
    double wanted = limitedAutomatic * rules->userMultiplier;

    // The card is the natural size without its transparent margin.
    double cardWidth = naturalSize.width - rules->cardMargin * 2;
    double cardHeight = naturalSize.height - rules->cardMargin * 2;
    if (cardWidth <= 0 || cardHeight <= 0) {
        return wanted;
    }

    double roomWidth = usableArea.width - rules->edgeGap * 2;
    double roomHeight = usableArea.height - rules->edgeGap * 2;
    if (roomWidth <= 0 || roomHeight <= 0) {
        return wanted;
    }

    double fitsWidth = roomWidth / cardWidth;
    double fitsHeight = roomHeight / cardHeight;
    double largestThatFits = smallerOf(fitsWidth, fitsHeight);
    return smallerOf(wanted, largestThatFits);
}

GLRect gl_clamp_panel(GLRect panel, double margin, GLRect area) {
    GLRect card = GLRect{panel.x + margin, panel.y + margin, panel.width - margin * 2, panel.height - margin * 2};

    double lowestX = area.x;
    double highestX = maxX(area) - card.width;
    double lowestY = area.y;
    double highestY = maxY(area) - card.height;

    // A card bigger than the area: keep its top-left corner visible.
    if (highestX < lowestX) {
        highestX = lowestX;
    }
    if (highestY < lowestY) {
        lowestY = highestY = maxY(area) - card.height;
    }

    double cardX = clampValue(card.x, lowestX, highestX);
    double cardY = clampValue(card.y, lowestY, highestY);

    GLRect result = panel;
    result.x = cardX - margin;
    result.y = cardY - margin;
    return result;
}

GLPlacement gl_placement_from_card(GLRect card, GLRect screenFrame) {
    GLPlacement placement = {};
    if (screenFrame.width <= 0 || screenFrame.height <= 0) {
        return placement;
    }
    double centreX = card.x + card.width / 2;
    double centreY = card.y + card.height / 2;
    placement.fractionX = (centreX - screenFrame.x) / screenFrame.width;
    placement.fractionY = (centreY - screenFrame.y) / screenFrame.height;
    return placement;
}

GLRect gl_card_from_placement(GLPlacement placement, GLSize cardSize, GLRect screenFrame) {
    double centreX = screenFrame.x + placement.fractionX * screenFrame.width;
    double centreY = screenFrame.y + placement.fractionY * screenFrame.height;
    return GLRect{centreX - cardSize.width / 2, centreY - cardSize.height / 2, cardSize.width, cardSize.height};
}

void gl_stack_cards(GLRect area,
                    const GLSize *cards,
                    int count,
                    double gap,
                    GLRect *outCards) {
    double columnRight = maxX(area);
    double top = maxY(area);
    double columnWidth = 0;

    for (int index = 0; index < count; index++) {
        GLSize size = cards[index];

        // This column is full: start another to the left of it.
        bool columnHasCards = top < maxY(area);
        bool wouldOverflow = top - size.height < area.y;
        if (columnHasCards && wouldOverflow) {
            columnRight -= columnWidth + gap;
            top = maxY(area);
            columnWidth = 0;
        }

        outCards[index] = GLRect{columnRight - size.width, top - size.height, size.width, size.height};
        top -= size.height + gap;
        columnWidth = largerOf(columnWidth, size.width);
    }
}
