#!/usr/bin/env python3
"""Generate Android Studio live templates (XML) and nvim LuaSnip snippets
(JSON) from the canonical .template.kt bodies in this directory.

Usage: generate.py [xml|json|all]   (default: all)

  xml  write compose_templates.xml and architecture_templates.xml to
       android/studio/
  json update nvim/snippets/kotlin.json, preserving any existing snippets
       that are not managed by this project
"""

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
XML_OUT_DIR = os.path.normpath(os.path.join(HERE, ".."))
KOTLIN_SNIPPETS = os.path.join(REPO, "nvim", "snippets", "kotlin.json")

# Managed nvim snippet prefixes (lowercase); these are regenerated from the
# canonical bodies and any matching entries are replaced on merge.
MANAGED_PREFIXES = {
    "compdetail",
    "compform",
    "compcard",
    "comptextfield",
    "compnavgraph",
    "compdomainmodel",
    "comprepository",
    "compusecase",
    "compentity",
    "compdao",
    "compdto",
    "compapi",
    "comprepositoryimpl",
    "compviewmodel",
}

# Display names used as keys in the nvim snippet JSON.
SNIPPET_NAMES = {
    "compDetail": "Jetpack Compose Detail Screen",
    "compForm": "Jetpack Compose Form Screen",
    "compCard": "Material 3 Card",
    "compTextField": "Outlined Text Field",
    "compNavGraph": "Compose Navigation Graph (Koin)",
    "compDomainModel": "Domain Model",
    "compRepository": "Repository Interface (Domain)",
    "compUseCase": "Use Case",
    "compEntity": "Room Entity",
    "compDao": "Room DAO (Flow + upserts)",
    "compDto": "Retrofit DTO (Gson)",
    "compApi": "Retrofit API Service",
    "compRepositoryImpl": "Hilt Repository Impl (Room + Retrofit)",
    "compViewModel": "Hilt ViewModel (MutableStateFlow)",
}

# (output file, group, [(abbreviation, description, body file,
#                        [(variable, expression, default, stop)] ...)] ...)
#
# Variable conventions:
#   - "Name" is the primary input (domain model name). It must be declared
#     first so it is the first tab stop, and so every derived variable can
#     reference it.
#   - Derived variables use IntelliJ expressions and never stop (they are
#     computed automatically); their parent must be declared earlier.
#   - `$END$` is a predefined IntelliJ variable: it stays in the template body
#     but is never declared as a <variable>.
#   - All derived names are driven by Name alone, so the user types the domain
#     name once and Repository/Dao/Api/Dto/Entity/UiState/... follow.
GROUPS = [
    (
        "compose_templates.xml",
        "Compose",
        [
            (
                "compDetail",
                "Generic Material3 detail screen with Scaffold, TopAppBar, and label/value rows",
                "detail_screen.template.kt",
                [
                    ("Name", "", "Item", "true"),
                    ("ScreenTitle", 'concat(snakeCase(Name), "_title")', "item_title", "false"),
                ],
            ),
            (
                "compForm",
                "Generic Material3 form screen with OutlinedTextFields, validation, and save button",
                "form_screen.template.kt",
                [
                    ("Name", "", "Item", "true"),
                    ("FieldOne", "", "title", "true"),
                    ("FieldTwo", "", "description", "true"),
                    ("LabelOne", 'concat(decapitalize(FieldOne), "_label")', "title_label", "false"),
                    ("LabelTwo", 'concat(decapitalize(FieldTwo), "_label")', "description_label", "false"),
                    ("ScreenTitle", 'concat(snakeCase(Name), "_form")', "item_form", "false"),
                ],
            ),
            (
                "compCard",
                "Material 3 card with title, body, and a click handler",
                "material_card.template.kt",
                [
                    ("Name", "", "Item", "true"),
                    ("Title", "", "Title", "true"),
                    ("Body", "", "Body text", "true"),
                ],
            ),
            (
                "compTextField",
                "OutlinedTextField with hoisted state, error, and keyboard options",
                "text_field.template.kt",
                [
                    ("Name", "", "Item", "true"),
                    ("label", "", "Label", "true"),
                ],
            ),
        ],
    ),
    (
        "architecture_templates.xml",
        "Architecture",
        [
            (
                "compDomainModel",
                "Domain model data class (id + fields)",
                "domain_model.template.kt",
                [
                    ("Name", "", "Item", "true"),
                    ("FieldOne", "", "title", "true"),
                    ("FieldTwo", "", "description", "true"),
                ],
            ),
            (
                "compRepository",
                "Repository interface (domain layer)",
                "repository_interface.template.kt",
                [
                    ("Name", "", "Item", "true"),
                    ("Repository", 'concat(Name, "Repository")', "ItemRepository", "false"),
                    ("item", "decapitalize(Name)", "item", "false"),
                ],
            ),
            (
                "compUseCase",
                "Singleton use case injecting the repository",
                "use_case.template.kt",
                [
                    ("Name", "", "Item", "true"),
                    ("Repository", 'concat(Name, "Repository")', "ItemRepository", "false"),
                ],
            ),
            (
                "compEntity",
                "Room entity with auto-generated primary key",
                "room_entity.template.kt",
                [
                    ("Name", "", "Item", "true"),
                    ("Entity", 'concat(Name, "Entity")', "ItemEntity", "false"),
                    ("tableName", "snakeCase(Name)", "item", "false"),
                    ("FieldOne", "", "title", "true"),
                    ("fieldOne", "decapitalize(FieldOne)", "title", "false"),
                    ("FieldTwo", "", "description", "true"),
                    ("fieldTwo", "decapitalize(FieldTwo)", "description", "false"),
                ],
            ),
            (
                "compDao",
                "Room DAO with Flow-based reads and upserts",
                "room_dao.template.kt",
                [
                    ("Name", "", "Item", "true"),
                    ("Dao", 'concat(Name, "Dao")', "ItemDao", "false"),
                    ("Entity", 'concat(Name, "Entity")', "ItemEntity", "false"),
                    ("Repository", 'concat(Name, "Repository")', "ItemRepository", "false"),
                    ("Api", 'concat(Name, "Api")', "ItemApi", "false"),
                    ("tableName", "snakeCase(Name)", "item", "false"),
                ],
            ),
            (
                "compDto",
                "Retrofit DTO with Gson serialized names",
                "retrofit_dto.template.kt",
                [
                    ("Name", "", "Item", "true"),
                    ("Dto", 'concat(Name, "Dto")', "ItemDto", "false"),
                    ("FieldOne", "", "title", "true"),
                    ("fieldOne", "decapitalize(FieldOne)", "title", "false"),
                    ("FieldTwo", "", "description", "true"),
                    ("fieldTwo", "decapitalize(FieldTwo)", "description", "false"),
                ],
            ),
            (
                "compApi",
                "Retrofit service interface (suspend endpoints)",
                "retrofit_api.template.kt",
                [
                    ("Name", "", "Item", "true"),
                    ("endpoint", "", "api/v1/items", "true"),
                    ("Api", 'concat(Name, "Api")', "ItemApi", "false"),
                    ("Dto", 'concat(Name, "Dto")', "ItemDto", "false"),
                ],
            ),
            (
                "compRepositoryImpl",
                "Hilt repository impl combining Room + Retrofit with mappers",
                "repository_impl.template.kt",
                [
                    ("Name", "", "Item", "true"),
                    ("Repository", 'concat(Name, "Repository")', "ItemRepository", "false"),
                    ("Dao", 'concat(Name, "Dao")', "ItemDao", "false"),
                    ("Api", 'concat(Name, "Api")', "ItemApi", "false"),
                    ("Dto", 'concat(Name, "Dto")', "ItemDto", "false"),
                    ("Entity", 'concat(Name, "Entity")', "ItemEntity", "false"),
                    ("item", "decapitalize(Name)", "item", "false"),
                    ("FieldOne", "", "title", "true"),
                    ("FieldTwo", "", "description", "true"),
                ],
            ),
            (
                "compViewModel",
                "Hilt ViewModel exposing MutableStateFlow-based UiState",
                "view_model.template.kt",
                [
                    ("Name", "", "Item", "true"),
                    ("Repository", 'concat(Name, "Repository")', "ItemRepository", "false"),
                    ("UiState", 'concat(Name, "UiState")', "ItemUiState", "false"),
                ],
            ),
            (
                "compNavGraph",
                "Nestable navigation graph wiring Koin ViewModels into Compose destinations",
                "nav_graph.template.kt",
                [
                    ("Name", "", "Home", "true"),
                    ("routeList", "", "home", "true"),
                    ("routeDetail", "", "detail", "true"),
                    ("ListViewModel", 'concat(Name, "ViewModel")', "HomeViewModel", "false"),
                    ("ListScreen", 'concat(Name, "Screen")', "HomeScreen", "false"),
                    ("DetailViewModel", 'concat(Name, "DetailViewModel")', "HomeDetailViewModel", "false"),
                    ("DetailScreen", 'concat(Name, "DetailScreen")', "HomeDetailScreen", "false"),
                ],
            ),
        ],
    ),
]


def read(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as fh:
        return fh.read()


def xml_esc(s):
    return (s.replace("&", "&amp;")
             .replace("<", "&lt;")
             .replace(">", "&gt;")
             .replace('"', "&quot;"))


def xml_attr(s):
    return xml_esc(s).replace("\n", "&#10;")


def generate_xml():
    for out_file, group, templates in GROUPS:
        lines = ['<?xml version="1.0" encoding="UTF-8"?>']
        lines.append(f'<templateSet group="{group}">')
        for abbr, desc, body_file, variables in templates:
            body = read(body_file).rstrip("\n")
            lines.append(
                f'  <template name="{abbr}" value="{xml_attr(body)}" '
                f'description="{xml_attr(desc)}" toReformat="true" toShortenFQNames="true">'
            )
            for name, expr, default, stop in variables:
                lines.append(
                    f'    <variable name="{xml_attr(name)}" expression="{xml_attr(expr)}" '
                    f'defaultValue="{xml_attr(default)}" alwaysStopAt="{stop}"/>'
                )
            lines.append('    <context>')
            lines.append('      <option name="KOTLIN_TOPLEVEL" value="true"/>')
            lines.append('    </context>')
            lines.append('  </template>')
        lines.append('</templateSet>')

        out_path = os.path.join(XML_OUT_DIR, out_file)
        with open(out_path, "w", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")
        print(f"Generated {out_path}")


def expand_for_snippet(body_file, variables):
    """Convert a template body to LuaSnip snippet text: editable variables
    become ${N:default} tabstops (in declaration order), derived variables
    and END are inlined / mapped to $0."""
    body = read(body_file).rstrip("\n")
    stop_vars = [(name, default) for name, _expr, default, stop in variables
                 if stop == "true" and name != "END"]
    index = {name: i + 1 for i, (name, _default) in enumerate(stop_vars)}

    for name, _expr, default, stop in variables:
        if name == "END":
            continue
        token = f"${name}$"
        if stop == "true":
            body = body.replace(token, "${%d:%s}" % (index[name], default))
        else:
            body = body.replace(token, default)
    body = body.replace("$END$", "$0")
    # Escape any remaining literal '$' (Kotlin string interpolation such as
    # $id) so LuaSnip emits it verbatim instead of treating it as a tabstop.
    body = re.sub(r"\$(?!\{)(?!\d)", r"\\$", body)
    return body


def update_json():
    data = {}
    if os.path.exists(KOTLIN_SNIPPETS):
        with open(KOTLIN_SNIPPETS, encoding="utf-8") as fh:
            data = json.load(fh)

    data = {k: v for k, v in data.items()
            if str(v.get("prefix", "")).lower() not in MANAGED_PREFIXES}

    for _out_file, _group, templates in GROUPS:
        for abbr, desc, body_file, variables in templates:
            text = expand_for_snippet(body_file, variables)
            name = SNIPPET_NAMES.get(abbr, desc)
            data[name] = {
                "prefix": abbr.lower(),
                "body": text.split("\n"),
                "description": desc,
            }

    os.makedirs(os.path.dirname(KOTLIN_SNIPPETS), exist_ok=True)
    with open(KOTLIN_SNIPPETS, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    print(f"Updated {KOTLIN_SNIPPETS}")


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "all"
    if mode in ("xml", "all"):
        generate_xml()
    if mode in ("json", "all"):
        update_json()


if __name__ == "__main__":
    main()
