const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const qml = readFileSync(path.join(__dirname, "..", "UnifiedTaskbar.qml"), "utf8");

function countOccurrences(source, needle) {
    let count = 0;
    let offset = 0;
    while (true) {
        const index = source.indexOf(needle, offset);
        if (index === -1)
            return count;
        count++;
        offset = index + needle.length;
    }
}

function uniqueAnchor(source, anchor, label) {
    assert.equal(countOccurrences(source, anchor), 1, `${label} anchor must occur exactly once`);
    return source.indexOf(anchor);
}

function extractBalanced(source, openingIndex, label) {
    assert.equal(source[openingIndex], "{", `${label} must start at an opening brace`);

    let depth = 0;
    let quote = null;
    let escaped = false;
    let lineComment = false;
    let blockComment = false;

    for (let index = openingIndex; index < source.length; index++) {
        const character = source[index];
        const nextCharacter = source[index + 1];

        if (lineComment) {
            if (character === "\n")
                lineComment = false;
            continue;
        }
        if (blockComment) {
            if (character === "*" && nextCharacter === "/") {
                blockComment = false;
                index++;
            }
            continue;
        }
        if (quote) {
            if (escaped) {
                escaped = false;
            } else if (character === "\\") {
                escaped = true;
            } else if (character === quote) {
                quote = null;
            }
            continue;
        }

        if (character === "/" && nextCharacter === "/") {
            lineComment = true;
            index++;
            continue;
        }
        if (character === "/" && nextCharacter === "*") {
            blockComment = true;
            index++;
            continue;
        }
        if (character === "'" || character === '"' || character === "`") {
            quote = character;
            continue;
        }
        if (character === "{") {
            depth++;
        } else if (character === "}") {
            depth--;
            if (depth === 0) {
                const extracted = source.slice(openingIndex, index + 1);
                assert.equal(extracted[0], "{", `${label} must include its opening boundary`);
                assert.equal(extracted.at(-1), "}", `${label} must include its closing boundary`);
                return extracted;
            }
            assert.ok(depth > 0, `${label} closed before its opening brace`);
        }
    }

    assert.fail(`${label} has no balanced closing brace`);
}

function extractAfterAnchor(source, anchor, label) {
    const anchorIndex = uniqueAnchor(source, anchor, label);
    const openingIndex = source.indexOf("{", anchorIndex + anchor.length);
    assert.notEqual(openingIndex, -1, `${label} must have an opening brace after its anchor`);
    return extractBalanced(source, openingIndex, label);
}

function extractAnchorBlock(source, anchor, label) {
    const anchorIndex = uniqueAnchor(source, anchor, label);
    const openingOffset = anchor.lastIndexOf("{");
    assert.ok(openingOffset >= 0, `${label} anchor must include its opening brace`);
    return extractBalanced(source, anchorIndex + openingOffset, label);
}

function extractBlockAroundAnchor(source, anchor, openingToken, label) {
    const anchorIndex = uniqueAnchor(source, anchor, label);
    const openingIndex = source.lastIndexOf(openingToken, anchorIndex);
    assert.notEqual(openingIndex, -1, `${label} must have an enclosing ${openingToken} block`);
    return extractBalanced(source, openingIndex + openingToken.lastIndexOf("{"), label);
}

function extractWorkspaceDelegate(source, id, label) {
    const idAnchor = `id: ${id}\n`;
    const idIndex = uniqueAnchor(source, idAnchor, label);
    const delegateToken = "delegate: Rectangle {";
    const openingIndex = source.lastIndexOf(delegateToken, idIndex);
    assert.notEqual(openingIndex, -1, `${label} must have a delegate block`);
    return extractBalanced(source, openingIndex + delegateToken.lastIndexOf("{"), label);
}

const switchToWorkspace = extractAfterAnchor(
    qml,
    "function switchToWorkspace(ws)",
    "switchToWorkspace(ws)",
);

const horizontalWorkspaceDelegate = extractWorkspaceDelegate(qml, "wsPill", "horizontal workspace delegate");
const verticalWorkspaceDelegate = extractWorkspaceDelegate(qml, "wsPillV", "vertical workspace delegate");
const horizontalWorkspaceMouseArea = extractBlockAroundAnchor(
    horizontalWorkspaceDelegate,
    "onClicked: root.switchToWorkspace(wsPill.wsData ? wsPill.wsData.workspace : null)",
    "MouseArea {",
    "horizontal workspace MouseArea",
);
const verticalWorkspaceMouseArea = extractBlockAroundAnchor(
    verticalWorkspaceDelegate,
    "onClicked: root.switchToWorkspace(wsPillV.wsData ? wsPillV.wsData.workspace : null)",
    "MouseArea {",
    "vertical workspace MouseArea",
);
const appEntryComponent = extractAnchorBlock(qml, "Component {\n        id: appEntryDelegate", "appEntryDelegate component");
const appEntryClickHandler = extractAfterAnchor(
    appEntryComponent,
    "onClicked: mouse =>",
    "app-entry onClicked handler",
);


test("workspace_switching_niri_uses_id", () => {
    assert.match(
        switchToWorkspace,
        /NiriService\.switchToWorkspace\(ws\.id\)/,
        "a Niri workspace fixture { id: 42, idx: 1 } must dispatch its stable id",
    );
    assert.doesNotMatch(
        switchToWorkspace,
        /NiriService\.switchToWorkspace\(ws\.idx\)/,
        "Niri must not dispatch the zero-based ordering index",
    );
});

test("workspace_switching_ignores_missing_workspace", () => {
    const guardIndex = switchToWorkspace.indexOf("if (!ws) return;");
    const dispatchIndex = switchToWorkspace.indexOf("NiriService.switchToWorkspace");

    assert.notEqual(guardIndex, -1, "switchToWorkspace must guard missing workspace data");
    assert.ok(guardIndex < dispatchIndex, "the missing-workspace guard must precede compositor dispatches");
});

test("workspace_switching_preserves_other_compositor_targets", () => {
    assert.match(switchToWorkspace, /Hyprland\.dispatch\(`workspace \$\{ws\.id\}`\)/);
    assert.match(switchToWorkspace, /DwlService\.setTags\(root\.effectiveScreenName, 1 << ws\.tag, 0\)/);
    assert.match(switchToWorkspace, /I3\.dispatch\(`workspace number \$\{ws\.num\}`\)/);
    assert.match(
        switchToWorkspace,
        /CompositorService\.isSway \|\| CompositorService\.isScroll \|\| CompositorService\.isMiracle/,
        "the I3 dispatch branch must retain Sway, Scroll, and Miracle",
    );
});

test("workspace_pill_handlers_preserve_shared_dispatch_and_app_activation", () => {
    assert.match(horizontalWorkspaceMouseArea, /root\.switchToWorkspace\(wsPill\.wsData \? wsPill\.wsData\.workspace : null\)/);
    assert.match(verticalWorkspaceMouseArea, /root\.switchToWorkspace\(wsPillV\.wsData \? wsPillV\.wsData\.workspace : null\)/);
    assert.ok(appEntryComponent.includes(appEntryClickHandler), "app-entry handler must be inside appEntryDelegate");
    assert.doesNotMatch(appEntryClickHandler, /root\.switchToWorkspace/);
    assert.ok(!appEntryClickHandler.includes(horizontalWorkspaceMouseArea));
    assert.ok(!appEntryClickHandler.includes(verticalWorkspaceMouseArea));

    const groupedCondition = appEntryClickHandler.indexOf("if (appEntry.isGrouped && appEntry.windowCount > 1)");
    const groupedCycle = appEntryClickHandler.indexOf("appEntry.entryData.windows[nextIndex].activate()");
    const directCondition = appEntryClickHandler.indexOf("else if (appEntry.toplevelData)");
    const directActivation = appEntryClickHandler.indexOf("appEntry.toplevelData.activate()");

    assert.ok(groupedCondition >= 0, "app clicks must retain grouped-window detection");
    assert.ok(groupedCondition < groupedCycle, "grouped-window cycling must follow grouped detection");
    assert.ok(groupedCycle < directCondition, "direct activation must remain the fallback after grouped cycling");
    assert.ok(directCondition < directActivation, "direct activation must follow the toplevel guard");
});
