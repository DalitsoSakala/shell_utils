#!/usr/bin/env python3
"""Scaffold a Django model and the related DRF feature files inside an existing app.

Appends (never overwrites) into an existing Django app, following the conventions
used in the CPD Hub backend (cpd-hub/backend):

  - models in <app>/models.py, managers in <app>/managers.py
  - admin registrations in <app>/admin.py
  - DRF stack in <app>/api/ (views.py, serializers.py, filters.py, urls.py)
  - app-level permission classes in <app>/permissions.py

Django REST Framework is used by default (serializer / viewset / filterset).

Run with the project's virtualenv python (when available) so that optional
dependencies such as ``djangondor``, ``shared_tools`` and ``drf_spectacular``
are detected and matched to the project conventions.
"""

from __future__ import annotations

import argparse
import importlib.util
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

# --------------------------------------------------------------------------- naming

def pascal(name: str) -> str:
    # Split on separators and on camelCase boundaries, then title-case each word.
    words: list[str] = []
    for part in re.split(r'[^A-Za-z0-9]+', name.strip()):
        words.extend(re.findall(r'[A-Z]+(?=[A-Z][a-z0-9]|\b)|[A-Z]?[a-z0-9]+', part))
    return ''.join(w[:1].upper() + w[1:].lower() if w else w for w in words)


def snake(name: str) -> str:
    name = re.sub(r'([a-z0-9])([A-Z])', r'\1_\2', name)
    name = re.sub(r'[^A-Za-z0-9]+', '_', name)
    return name.lower().strip('_')


def kebab(name: str) -> str:
    return snake(name).replace('_', '-')


def plural(name: str) -> str:
    if re.search(r'[^aeiouAEIOU]y$', name):
        return name[:-1] + 'ies'
    if re.search(r'is$', name):
        return name[:-2] + 'es'
    if re.search(r'(s|x|z|ch|sh)$', name):
        return name + 'es'
    return name + 's'


# --------------------------------------------------------------------------- fields

FIELD_ALIASES = {
    'char': 'CharField', 'charfield': 'CharField', 'str': 'CharField', 'string': 'CharField',
    'text': 'TextField', 'textfield': 'TextField',
    'int': 'IntegerField', 'integer': 'IntegerField', 'integerfield': 'IntegerField',
    'pint': 'PositiveIntegerField', 'positiveint': 'PositiveIntegerField',
    'positiveintegerfield': 'PositiveIntegerField',
    'bigint': 'BigIntegerField', 'bigintegerfield': 'BigIntegerField',
    'float': 'FloatField', 'floatfield': 'FloatField',
    'decimal': 'DecimalField', 'decimalfield': 'DecimalField',
    'bool': 'BooleanField', 'boolean': 'BooleanField', 'booleanfield': 'BooleanField',
    'date': 'DateField', 'datefield': 'DateField',
    'datetime': 'DateTimeField', 'datetimefield': 'DateTimeField',
    'time': 'TimeField', 'timefield': 'TimeField',
    'json': 'JSONField', 'jsonfield': 'JSONField',
    'array': 'ArrayField', 'arrayfield': 'ArrayField',
    'uuid': 'UUIDField', 'uuidfield': 'UUIDField',
    'slug': 'SlugField', 'slugfield': 'SlugField',
    'email': 'EmailField', 'emailfield': 'EmailField',
    'url': 'URLField', 'urlfield': 'URLField',
    'file': 'FileField', 'filefield': 'FileField',
    'image': 'ImageField', 'imagefield': 'ImageField',
    'fk': 'ForeignKey', 'foreignkey': 'ForeignKey',
    'o2o': 'OneToOneField', 'onetoone': 'OneToOneField', 'onetoonefield': 'OneToOneField',
    'm2m': 'ManyToManyField', 'manytomany': 'ManyToManyField', 'manytomanyfield': 'ManyToManyField',
}

RELATION_FIELDS = {'ForeignKey', 'OneToOneField', 'ManyToManyField'}
CHAR_FIELDS = {'CharField', 'SlugField', 'EmailField', 'URLField'}
NUMERIC_FIELDS = {'IntegerField', 'PositiveIntegerField', 'BigIntegerField', 'FloatField', 'DecimalField'}
DATE_FIELDS = {'DateField', 'DateTimeField', 'TimeField'}
FILE_FIELDS = {'FileField', 'ImageField'}


@dataclass
class Field:
    name: str
    ftype: str
    target: str | None = None
    nullable: bool = False
    opts: list[str] = field(default_factory=list)


def parse_fields(raw: str) -> list[Field]:
    """Parse a comma-separated field list.

    Each token: ``name`` | ``name:Type`` | ``name:Type:options``
    A trailing ``?`` marks the field nullable, e.g. ``owner:FK:User?``.
    Relations use a target: ``owner:FK:User``, ``groups:M2M:Role``, ``profile:O2O:User``.
    Options are verbatim kwargs separated by ``;`` (so commas stay field
    separators): ``description:CharField:max_length=200`` or
    ``amount:Decimal:max_digits=10;decimal_places=2``.
    Shorthand: ``name:CharField:255`` -> max_length=255.
    """
    fields: list[Field] = []
    for token in raw.split(','):
        token = token.strip()
        if not token:
            continue
        nullable = token.endswith('?')
        if nullable:
            token = token[:-1]
        parts = [p.strip() for p in token.split(':')]
        if not parts[0]:
            continue
        name = snake(parts[0])
        ftype = 'CharField'
        target = None
        opts: list[str] = []
        if len(parts) >= 2:
            ftype = FIELD_ALIASES.get(parts[1].lower(), parts[1])
        if ftype in RELATION_FIELDS:
            if len(parts) > 2:
                target = parts[2]
                if target.endswith('?'):
                    target = target[:-1]
                    nullable = True
            if not target:
                target = 'self'
            if ftype == 'ManyToManyField':
                nullable = False
        else:
            if len(parts) > 2:
                rest = parts[2]
                if rest.isdigit() and ftype in CHAR_FIELDS:
                    opts.append(f'max_length={rest}')
                else:
                    opts.extend(o.strip() for o in rest.split(';') if o.strip())
        fields.append(Field(name=name, ftype=ftype, target=target, nullable=nullable, opts=opts))
    return fields


def djangondor_nullable_marker(f: Field) -> str | None:
    """Which djangondor marker is used for a nullable field, if any."""
    if not f.nullable:
        return None
    if f.ftype in CHAR_FIELDS and not f.opts:
        return 'NULLABLE_CHARFIELD'
    return 'NULLABLE'


def render_field(f: Field, use_djangondor: bool, related: str) -> str:
    indent = '    '
    if f.ftype in ('ForeignKey', 'OneToOneField'):
        args = [f"'{f.target}'"]
        if f.nullable:
            args.append('on_delete=models.SET_NULL')
            args.extend(_nullable_kwargs(use_djangondor, []))
        else:
            args.append('on_delete=models.CASCADE')
        args.append(f"related_name='{related}'")
        return f"{indent}{f.name} = models.{f.ftype}({', '.join(args)})"
    if f.ftype == 'ManyToManyField':
        args = [f"'{f.target}'"]
        args.extend(f.opts)
        args.append(f"related_name='{related}'")
        return f"{indent}{f.name} = models.{f.ftype}({', '.join(args)})"
    if f.ftype == 'ArrayField':
        args = ['models.CharField(max_length=255)']
        args.extend(_nullable_kwargs(use_djangondor, f.opts))
        return f"{indent}{f.name} = ArrayField({', '.join(args)})"

    opts = list(f.opts)
    if f.ftype in CHAR_FIELDS and not any(o.startswith('max_length=') for o in opts):
        opts.insert(0, 'max_length=255')
    if f.ftype in FILE_FIELDS and not any(o.startswith('upload_to=') for o in opts):
        opts.insert(0, "upload_to='files/'")

    if f.nullable and use_djangondor and f.ftype in CHAR_FIELDS and not f.opts:
        return f"{indent}{f.name} = models.{f.ftype}(**NULLABLE_CHARFIELD)"

    if f.nullable:
        opts = _nullable_kwargs(use_djangondor, opts)
    if not opts:
        return f"{indent}{f.name} = models.{f.ftype}()"
    return f"{indent}{f.name} = models.{f.ftype}({', '.join(opts)})"


def _nullable_kwargs(use_djangondor: bool, opts: list[str]) -> list[str]:
    opts = list(opts)
    if any(o.startswith('default=') for o in opts):
        opts = [o for o in opts if not o.startswith('default=')]
        return opts + ['null=True', 'blank=True']
    if use_djangondor:
        return opts + ['**NULLABLE']
    return opts + ['null=True', 'blank=True', 'default=None']


# --------------------------------------------------------------------------- file helpers

DRY_RUN = False


def write_file(path: Path, text: str) -> None:
    if DRY_RUN:
        print(f'  (dry-run) would write {path}')
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)


def read_lines(path: Path) -> list[str]:
    if path.exists():
        return path.read_text().splitlines()
    return []


def imported_names(content: str, module: str) -> set[str]:
    names: set[str] = set()
    mod = re.escape(module)
    from_pat = re.compile(r'^\s*from\s+' + mod + r'\s+import\s+([^\n]+)$', re.MULTILINE)
    for m in from_pat.finditer(content):
        body = m.group(1).strip()
        body = body.strip('()')
        for part in body.split(','):
            part = part.strip()
            if part and part != '...':
                names.add(part.split(' as ')[0].strip())
    # ES module style: `import { A, B } from "mod"` / `import X from "mod"` / `import type { X } from "mod"`
    es_pat = re.compile(r'^\s*import\s+(.*?)\s+from\s+["\']' + mod + r'["\']\s*$', re.MULTILINE)
    for m in es_pat.finditer(content):
        body = m.group(1).strip()
        if body.startswith('type '):
            body = body[5:].strip()
        if body.startswith('{') and body.endswith('}'):
            for part in body[1:-1].split(','):
                part = part.strip()
                if part:
                    names.add(part.split(' as ')[0].strip())
        elif body:
            names.add(body.split(' as ')[0].strip())
    return names


def last_top_import_index(lines: list[str]) -> int:
    idx = -1
    for i, line in enumerate(lines):
        stripped = line.lstrip()
        if line.startswith(' ') or line.startswith('\t'):
            continue
        if re.match(r'^(from\s+\S+\s+import|import\s+)', stripped):
            idx = i
    return idx


def ensure_imports(path: Path, statements: list[str]) -> list[str]:
    """Return file lines with any missing import statements inserted after the last import."""
    lines = read_lines(path)
    if not statements:
        return lines
    content = '\n'.join(lines)
    missing: list[str] = []
    for stmt in statements:
        m = re.match(r'^from\s+(\S+)\s+import\s+(.+)$', stmt)
        if not m:
            m2 = re.match(r'^import\s+(.+?)\s+from\s+["\']([^"\']+)["\']$', stmt)
            if m2:
                module, names_part = m2.group(2), m2.group(1)
                body = names_part.strip()
                is_type = body.startswith('type ')
                if is_type:
                    body = body[5:].strip()
                if body.startswith('{') and body.endswith('}'):
                    needed = [n.strip() for n in body[1:-1].split(',') if n.strip()]
                    existing = imported_names(content, module)
                    need = [n for n in needed if n not in existing]
                    if need:
                        merged = False
                        for i, line in enumerate(lines):
                            m_line = re.match(
                                r'^\s*import\s+(type\s+)?\{([^}]*)\}\s+from\s+["\']' + re.escape(module) + r'["\']\s*$',
                                line,
                            )
                            if m_line:
                                names = [n.strip() for n in m_line.group(2).split(',') if n.strip()]
                                plain = {n[5:] if n.startswith('type ') else n for n in names}
                                add = [n for n in need if (n[5:] if n.startswith('type ') else n) not in plain]
                                if add:
                                    kw = 'type ' if (is_type or m_line.group(1)) else ''
                                    indent = line[:len(line) - len(line.lstrip())]
                                    lines[i] = f'{indent}import {kw}{{ {", ".join(names + add)} }} from "{module}"'
                                merged = True
                                break
                        if not merged:
                            missing.append(f'import {("type " if is_type else "")}{{ {", ".join(need)} }} from "{module}"')
                else:
                    if body not in imported_names(content, module):
                        missing.append(stmt)
                continue
            if stmt not in content:
                missing.append(stmt)
            continue
        module, names_part = m.group(1), m.group(2)
        needed = [n.strip() for n in names_part.split(',')]
        existing = imported_names(content, module)
        need = [n for n in needed if n not in existing]
        if need:
            missing.append(f'from {module} import {", ".join(need)}')
    if not missing:
        return lines
    idx = last_top_import_index(lines)
    lines[idx + 1:idx + 1] = missing
    return lines


def ensure_line(lines: list[str], statement: str) -> list[str]:
    if any(l.strip() == statement for l in lines):
        return lines
    idx = last_top_import_index(lines)
    lines[idx + 1:idx + 1] = [statement]
    return lines


def trim_trailing_blank(lines: list[str]) -> list[str]:
    while lines and lines[-1] == '':
        lines.pop()
    return lines


def class_exists(content: str, class_name: str) -> bool:
    return bool(re.search(r'^\s*class\s+' + re.escape(class_name) + r'\b', content, re.MULTILINE))


def interface_exists(content: str, name: str) -> bool:
    return bool(re.search(r'^\s*interface\s+' + re.escape(name) + r'\b', content, re.MULTILINE))


def admin_registered(content: str, name: str) -> bool:
    return f'@admin.register({name})' in content or f'admin.site.register({name})' in content


def append_module(path: Path, imports: list[str], body: str, exists_check) -> tuple[str, str]:
    """Append ``body`` to ``path``, ensuring ``imports`` are present.

    Returns (action, detail): ('added', ...) or ('skipped', ...).
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    content = path.read_text() if path.exists() else ''
    if exists_check(content):
        return 'skipped', f'{path} already contains the scaffold'
    lines = ensure_imports(path, imports)
    lines = trim_trailing_blank(lines)
    lines += ['', '', body]
    write_file(path, '\n'.join(lines).rstrip() + '\n')
    return 'added', str(path)


# --------------------------------------------------------------------------- builders

def model_imports(name: str, base: str, fields: list[Field], use_djangondor: bool, use_manager: bool) -> list[str]:
    imports = ['from django.db import models']
    if use_djangondor:
        dnames: set[str] = set()
        if base == 'BaseTimestampModel':
            dnames.add('BaseTimestampModel')
        for f in fields:
            marker = djangondor_nullable_marker(f)
            if marker:
                dnames.add(marker)
        if dnames:
            imports.append('from djangondor.models import ' + ', '.join(sorted(dnames)))
    if any(f.ftype == 'ArrayField' for f in fields):
        imports.append('from django.contrib.postgres.fields import ArrayField')
    if use_manager:
        imports.append(f'from .managers import {name}Manager')
    return imports


def build_model_body(name: str, base: str, fields: list[Field], use_djangondor: bool, use_manager: bool) -> str:
    related = f'{snake(name)}s'
    lines = [f'class {name}({base}):']
    for f in fields:
        lines.append(render_field(f, use_djangondor, related))
    if fields:
        lines.append('')
    if use_manager:
        lines.append(f'    objects = {name}Manager()')
        lines.append('')
    first = fields[0].name if fields else 'pk'
    lines.append('    def __str__(self) -> str:')
    lines.append(f'        return f"{{self.{first}}}"')
    return '\n'.join(lines)


def build_manager_imports() -> list[str]:
    return ['from django.db.models import Manager, QuerySet']


def build_manager_body(name: str) -> str:
    return (
        f'class {name}Manager(Manager):\n'
        f'    def get_queryset(self) -> QuerySet:\n'
        f'        return super().get_queryset()'
    )


def build_admin_imports(name: str) -> list[str]:
    return ['from django.contrib import admin', f'from .models import {name}']


def build_admin_body(name: str, fields: list[Field]) -> str:
    display = ['id'] + [f.name for f in fields][:5]
    search = ['id'] + [f.name for f in fields if f.ftype in CHAR_FIELDS][:3]
    display = list(dict.fromkeys(display))
    search = list(dict.fromkeys(search))
    lines = [f'@admin.register({name})', f'class {name}Admin(admin.ModelAdmin):']
    lines.append(f"    list_display = {', '.join(repr(x) for x in display)}")
    lines.append(f"    search_fields = {', '.join(repr(x) for x in search)}")
    return '\n'.join(lines)


def build_serializer_imports(name: str) -> list[str]:
    return ['from rest_framework import serializers', f'from ..models import {name}']


def build_serializer_body(name: str) -> str:
    return (
        f'class {name}Serializer(serializers.ModelSerializer):\n'
        f'    class Meta:\n'
        f'        model = {name}\n'
        f"        fields = '__all__'"
    )


def build_filterset_imports(name: str) -> list[str]:
    return ['from django_filters import rest_framework as filters', f'from ..models import {name}']


def build_filterset_body(name: str, fields: list[Field]) -> str:
    lines = [f'class {name}Filter(filters.FilterSet):']
    for f in fields:
        if f.ftype in CHAR_FIELDS:
            lines.append(f"    {f.name} = filters.CharFilter(lookup_expr='icontains')")
        elif f.ftype in NUMERIC_FIELDS:
            lines.append(f'    {f.name} = filters.NumberFilter(lookup_expr="exact")')
        elif f.ftype == 'DateTimeField':
            lines.append(f'    {f.name} = filters.DateTimeFilter(lookup_expr="exact")')
        elif f.ftype in DATE_FIELDS:
            lines.append(f'    {f.name} = filters.DateFilter(lookup_expr="exact")')
        elif f.ftype == 'BooleanField':
            lines.append(f'    {f.name} = filters.BooleanFilter()')
        elif f.ftype in RELATION_FIELDS:
            lines.append(f'    {f.name}__id = filters.NumberFilter(field_name="{f.name}__id", lookup_expr="exact")')
    lines.append('')
    lines.append('    class Meta:')
    lines.append(f'        model = {name}')
    lines.append("        fields = '__all__'")
    return '\n'.join(lines)


def build_permission_imports() -> list[str]:
    return [
        'from rest_framework.permissions import SAFE_METHODS, BasePermission',
        'from rest_framework.settings import api_settings',
    ]


def build_permission_body(name: str, content: str) -> str:
    upper = snake(name).upper()
    lines = [
        f'class {name}Access(BasePermission):',
        f'    """Access control for {name} endpoints."""',
        '',
        '    def has_permission(self, request, view):',
        '        user = request.user',
        '        if not user.is_authenticated:',
        '            return False',
        '        if request.method in SAFE_METHODS:',
        '            return True',
        '        return bool(user.is_staff or user.is_superuser)',
        '',
        f'PERM_{upper} = *_DEF, {name}Access',
    ]
    if '_DEF = api_settings.DEFAULT_PERMISSION_CLASSES' not in content:
        lines.insert(0, '_DEF = api_settings.DEFAULT_PERMISSION_CLASSES')
        lines.insert(1, '')
        lines.insert(2, '')
    return '\n'.join(lines)


def build_view_imports(name: str, use_scaffold_perms: bool, use_shared_tools_perms: bool, use_extend_schema: bool) -> list[str]:
    imports = ['from rest_framework import viewsets']
    if use_extend_schema:
        imports.append('from drf_spectacular.utils import extend_schema')
    imports.append(f'from ..models import {name}')
    imports.append(f'from .filters import {name}Filter')
    imports.append(f'from .serializers import {name}Serializer')
    if use_shared_tools_perms:
        imports.append('from shared_tools.api.permissions import PERM_INTERNAL_COLLEAGUE')
    elif use_scaffold_perms:
        imports.append(f'from .permissions import PERM_{snake(name).upper()}')
    return imports


def build_view_body(name: str, app_title: str, use_scaffold_perms: bool, use_shared_tools_perms: bool, use_extend_schema: bool) -> str:
    upper = snake(name).upper()
    lines = []
    if use_extend_schema:
        lines += [
            '@extend_schema(',
            f"    tags=['{app_title}'],",
            f"    description='CRUD operations for {name}',",
            '    responses={',
            f'        200: {name}Serializer(many=True),',
            "        400: 'Bad Request',",
            '    },',
            ')',
        ]
    lines.append(f'class {name}ViewSet(viewsets.ModelViewSet):')
    lines.append(f"    queryset = {name}.objects.all().order_by('-id')")
    lines.append(f'    serializer_class = {name}Serializer')
    lines.append(f'    filterset_class = {name}Filter')
    if use_shared_tools_perms:
        lines.append('    permission_classes = PERM_INTERNAL_COLLEAGUE')
    elif use_scaffold_perms:
        lines.append(f'    permission_classes = PERM_{upper}')
    return '\n'.join(lines)


URL_IMPORTS = [
    'from django.urls import include, path',
    'from rest_framework import routers',
    'from . import views',
]


def url_register_line(name: str) -> str:
    sn = snake(name)
    route = kebab(plural(sn))
    return f"router.register('{route}', views.{name}ViewSet, basename='{sn}')"


def append_url_register(path: Path, name: str) -> tuple[str, str]:
    reg_line = url_register_line(name)
    path.parent.mkdir(parents=True, exist_ok=True)
    content = path.read_text() if path.exists() else ''
    if reg_line in content:
        return 'skipped', f'{path} already registers {name}ViewSet'
    if not content.strip():
        lines = list(URL_IMPORTS)
        lines += ['', 'router = routers.DefaultRouter()', '', reg_line, '',
                  'urlpatterns = [', "    path('', include(router.urls)),", ']']
        write_file(path, '\n'.join(lines).rstrip() + '\n')
        return 'added', str(path)
    lines = ensure_imports(path, URL_IMPORTS)
    lines = ensure_line(lines, 'router = routers.DefaultRouter()')
    idx_reg = max((i for i, l in enumerate(lines) if l.lstrip().startswith('router.register(')), default=-1)
    idx_urp = next((i for i, l in enumerate(lines) if l.strip().startswith('urlpatterns')), None)
    if idx_reg >= 0:
        lines.insert(idx_reg + 1, reg_line)
    elif idx_urp is not None:
        lines.insert(idx_urp, reg_line)
    else:
        lines = trim_trailing_blank(lines) + ['', reg_line, '',
                                              'urlpatterns = [', "    path('', include(router.urls)),", ']']
    write_file(path, '\n'.join(lines).rstrip() + '\n')
    return 'added', str(path)


# --------------------------------------------------------------------------- ETL / tasks / TS client

def ts_field_type(f: Field) -> str:
    ref = '{ id: number; name?: string | null }'
    if f.ftype in RELATION_FIELDS:
        if f.ftype == 'ManyToManyField':
            return f'Array<{ref}>'
        return f'{ref} | null' if f.nullable else ref
    if f.ftype in NUMERIC_FIELDS:
        t = 'number'
    elif f.ftype == 'BooleanField':
        t = 'boolean'
    elif f.ftype == 'JSONField':
        t = 'unknown'
    elif f.ftype == 'ArrayField':
        t = 'unknown[]'
    else:
        t = 'string'
    return f'{t} | null' if f.nullable else t


def build_types_imports() -> list[str]:
    return []


def build_types_body(name: str, fields: list[Field], has_timestamps: bool) -> str:
    # Ambient interface, following the frontend/typings/*.d.ts convention: the
    # file declares global interfaces that need no explicit import.
    lines = [f'interface {name} {{', '  id: number']
    for f in fields:
        lines.append(f'  {f.name}: {ts_field_type(f)}')
    if has_timestamps:
        lines.append('  created_at?: string')
        lines.append('  updated_at?: string')
    lines.append('}')
    return '\n'.join(lines)


def build_api_imports() -> list[str]:
    # Typings are ambient globals (frontend/typings/*.d.ts), so api.ts only
    # imports the shared ApiClient helpers.
    return [
        'import { ApiClient } from "Tools/api/client"',
        'import { processResponse, processResultsResponse } from "Tools/api/helpers"',
    ]


def build_api_body(name: str) -> str:
    sn = snake(name)
    plural_pascal = pascal(plural(sn))
    base_const = f'{sn.upper()}_BASE'
    base = kebab(plural(sn))
    return (
        f'const {base_const} = "{base}/"\n'
        f'\n'
        f'export async function list{plural_pascal}(\n'
        f'  params: Record<string, string | number | undefined> = {{}}\n'
        f') {{\n'
        f'  return processResultsResponse<{name}[]>(await ApiClient.get({base_const}, {{ params }}))\n'
        f'}}\n'
        f'\n'
        f'export async function retrieve{name}(id: number) {{\n'
        f'  return processResponse<{name}>(await ApiClient.get(`${{{base_const}}}${{id}}/`))\n'
        f'}}\n'
        f'\n'
        f'export async function create{name}(body: Partial<{name}>) {{\n'
        f'  return processResponse<{name}>(await ApiClient.post({base_const}, body))\n'
        f'}}\n'
        f'\n'
        f'export async function update{name}(id: number, body: Partial<{name}>) {{\n'
        f'  return processResponse<{name}>(await ApiClient.patch(`${{{base_const}}}${{id}}/`, body))\n'
        f'}}\n'
        f'\n'
        f'export async function remove{name}(id: number) {{\n'
        f'  return processResponse(await ApiClient.delete(`${{{base_const}}}${{id}}/`))\n'
        f'}}'
    )


def build_sql_body(sql_name: str, model: str, app: str, etl_fn: str) -> str:
    return (
        f'-- {sql_name}.sql\n'
        f'-- ETL query feeding {app}.data_etl.{snake(model)}_etl.{etl_fn}\n'
        f'-- Write the query below.\n'
        f'SELECT 1;'
    )


def build_etl_body(model: str, sql_name: str, etl_fn: str, etl_lib: str = 'pandas') -> str:
    lib_import = 'import polars as pl' if etl_lib == 'polars' else 'import pandas as pd'
    header = (
        f'"""ETL processing for {model}.\n'
        f'\n'
        f'SQL query: data_etl/queries/{sql_name}.sql\n'
        f'"""\n'
        f'from pathlib import Path\n'
        f'\n'
        f'{lib_import}\n'
        f'from django.db import connection\n'
        f'\n'
        f'_QUERY_FILE = Path(__file__).resolve().parent / "queries" / "{sql_name}.sql"\n'
        f'\n'
        f'\n'
    )
    if etl_lib == 'polars':
        return header + (
            f'def {etl_fn}(sql_path: str | Path | None = None) -> pl.DataFrame:\n'
            f'    """Run the {sql_name} query and return its rows as a polars DataFrame.\n'
            f'\n'
            f'    Customize this to map rows into {model} records (upsert / bulk_create).\n'
            f'    """\n'
            f'    path = Path(sql_path) if sql_path else _QUERY_FILE\n'
            f'    with connection.cursor() as cursor:\n'
            f'        cursor.execute(path.read_text())\n'
            f'        columns = [col[0] for col in cursor.description]\n'
            f'        rows = cursor.fetchall()\n'
            f'    return pl.DataFrame(rows, schema=columns, orient="row")'
        )
    return header + (
        f'def {etl_fn}(sql_path: str | Path | None = None) -> pd.DataFrame:\n'
        f'    """Run the {sql_name} query and return its rows as a pandas DataFrame.\n'
        f'\n'
        f'    Customize this to map rows into {model} records (upsert / bulk_create).\n'
        f'    """\n'
        f'    path = Path(sql_path) if sql_path else _QUERY_FILE\n'
        f'    with connection.cursor() as cursor:\n'
        f'        cursor.execute(path.read_text())\n'
        f'        columns = [col[0] for col in cursor.description]\n'
        f'        rows = cursor.fetchall()\n'
        f'    return pd.DataFrame(rows, columns=columns)'
    )


def build_command_body(app: str, model: str, sql_name: str, etl_fn: str) -> str:
    sn = snake(model)
    return (
        f'from django.core.management.base import BaseCommand\n'
        f'\n'
        f'from {app}.data_etl.{sn}_etl import {etl_fn}\n'
        f'\n'
        f'\n'
        f'class Command(BaseCommand):\n'
        f'    help = "Run the {sql_name} ETL query for {app}.{model}."\n'
        f'\n'
        f'    def add_arguments(self, parser):\n'
        f'        parser.add_argument(\n'
        f'            "--sql-name",\n'
        f'            default="{sql_name}",\n'
        f'            help="SQL query file name (without .sql) in data_etl/queries.",\n'
        f'        )\n'
        f'        parser.add_argument(\n'
        f'            "--dry-run",\n'
        f'            action="store_true",\n'
        f'            help="Only count rows; do not write anything.",\n'
        f'        )\n'
        f'\n'
        f'    def handle(self, *args, **options):\n'
        f'        sql_name = options["sql_name"]\n'
        f'        rows = {etl_fn}(f"{{sql_name}}.sql")\n'
        f'        self.stdout.write(\n'
        f'            self.style.SUCCESS(\n'
        f'                f"Processed {{len(rows)}} rows from data_etl/queries/{{sql_name}}.sql"\n'
        f'            )\n'
        f'        )'
    )


def build_dc_task_imports(app: str, model: str, etl_fn: str) -> list[str]:
    # developer_console/tasks.py already imports `shared_task`, `ExposedTaskName`
    # and defines `run_tracked`; only the app ETL import is new.
    return [f'from {app}.data_etl.{snake(model)}_etl import {etl_fn}']


def build_dc_task_body(app: str, model: str, etl_fn: str, const: str, slug: str) -> str:
    return (
        f'@shared_task\n'
        f'def celery_{slug}():\n'
        f'    run_tracked(ExposedTaskName.{const}, {etl_fn})'
    )


def ensure_exposed_task_name(path: Path, const: str, slug: str) -> tuple[str, str, str]:
    """Add ``<CONST>=TASK_PREFIX+'<slug>'`` to the ExposedTaskName class in values.py."""
    rel = f'developer_console/values.py'
    content = path.read_text() if path.exists() else ''
    if not content:
        return rel, 'error', f'{path} not found'
    if f'{const}=' in content:
        return rel, 'skipped', f'{path} already defines {const}'
    lines = content.splitlines()
    cls_idx = None
    for i, line in enumerate(lines):
        if line.startswith('class ExposedTaskName:'):
            cls_idx = i
            break
    if cls_idx is None:
        return rel, 'error', f'ExposedTaskName class not found in {path}'
    insert_at = len(lines)
    for i in range(cls_idx + 1, len(lines)):
        if lines[i].startswith('    @staticmethod') or lines[i].startswith('    def '):
            insert_at = i
            break
    lines.insert(insert_at, f'    {const}=TASK_PREFIX+\'{slug}\'')
    write_file(path, '\n'.join(lines).rstrip() + '\n')
    return rel, 'added', str(path)


def append_beat_schedule(path: Path, slug: str) -> tuple[str, str, str]:
    """Append a crontab section for ``slug`` to configs/celery-beat.ini."""
    rel = 'configs/celery-beat.ini'
    content = path.read_text() if path.exists() else ''
    if f'[{slug}]' in content:
        return rel, 'skipped', f'{path} already schedules {slug}'
    entry = f'[{slug}]\nschedule = {{\'minute\': 0, \'hour\': 3}}\n'
    write_file(path, (content.rstrip() + '\n\n' + entry) if content else entry)
    return rel, 'added', str(path)


def api_list_fn(name: str) -> str:
    return f'list{pascal(plural(snake(name)))}'


# --------------------------------------------------------------------------- main

def module_available(name: str) -> bool:
    return importlib.util.find_spec(name) is not None


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description='Scaffold a Django model + DRF feature files into an app.')
    ap.add_argument('--root', required=True, help='Django project root (dir containing manage.py)')
    ap.add_argument('--app', required=True, help='Django app name')
    ap.add_argument('--name', required=True, help='Model name, e.g. Farmer')
    ap.add_argument('--fields', default='', help='Comma-separated fields, e.g. name,age:Int,owner:FK:User?')
    ap.add_argument('--base', default='auto', help='Base model class (auto | models.Model | BaseTimestampModel | other)')
    ap.add_argument('--manager', type=int, default=1)
    ap.add_argument('--admin', type=int, default=0)
    ap.add_argument('--serializer', type=int, default=0)
    ap.add_argument('--viewset', type=int, default=0)
    ap.add_argument('--filterset', type=int, default=0)
    ap.add_argument('--urls', type=int, default=0)
    ap.add_argument('--permissions', type=int, default=0)
    ap.add_argument('--permission-source', default='scaffold', choices=['scaffold', 'shared_tools'])
    ap.add_argument('--etl', type=int, default=0, help='Create data_etl package with a SQL query + processing function')
    ap.add_argument('--etl-lib', default='pandas', choices=['pandas', 'polars'], help='DataFrame library for the ETL processing function (default: pandas)')
    ap.add_argument('--sql-name', default='', help='SQL query file name (without .sql) in data_etl/queries')
    ap.add_argument('--etl-function', default='', help='Query processing function name in data_etl')
    ap.add_argument('--command', type=int, default=0, help='Create a management command to run the ETL')
    ap.add_argument('--command-name', default='', help='Management command name (default: app name)')
    ap.add_argument('--celery', type=int, default=0, help='Register a Celery worker task in developer_console/tasks.py + beat entry')
    ap.add_argument('--api-client', type=int, default=0, help='Create frontend TypeScript api.ts + ambient typings .d.ts')
    ap.add_argument('--frontend-dir', default='', help='Frontend feature dir for api.ts (default: <root>/frontend/src/Data/<app>)')
    ap.add_argument('--typings-file', default='', help='Frontend typings file for the model interface (default: <root>/frontend/typings/<app>.d.ts)')
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args(argv)

    global DRY_RUN
    DRY_RUN = args.dry_run

    root = Path(args.root).resolve()
    # Make local project apps (e.g. shared_tools) importable for detection.
    if str(root) not in sys.path:
        sys.path.insert(0, str(root))
    app_dir = root / args.app
    if not app_dir.is_dir():
        print(f"Error: app directory '{app_dir}' does not exist.", file=sys.stderr)
        return 1

    name = pascal(args.name)
    if not name:
        print('Error: model name is required.', file=sys.stderr)
        return 1

    fields = parse_fields(args.fields)
    if not fields:
        print('Error: at least one field is required.', file=sys.stderr)
        return 1

    djangondor_ok = module_available('djangondor')
    base = args.base
    if base == 'auto':
        base = 'BaseTimestampModel' if djangondor_ok else 'models.Model'
    if base == 'BaseTimestampModel' and not djangondor_ok:
        print("Warning: 'djangondor' not importable; falling back to models.Model.", file=sys.stderr)
        base = 'models.Model'
    use_djangondor = djangondor_ok and base != 'models.Model'

    use_shared_tools = args.permission_source == 'shared_tools' and module_available('shared_tools')
    if args.permission_source == 'shared_tools' and not use_shared_tools:
        print("Warning: 'shared_tools' not importable; falling back to an app-level permission class.", file=sys.stderr)
    use_extend_schema = module_available('drf_spectacular')

    use_scaffold_perms = bool(args.permissions) and not use_shared_tools
    use_manager = bool(args.manager)
    use_admin = bool(args.admin)
    use_serializer = bool(args.serializer)
    use_viewset = bool(args.viewset)
    use_filterset = bool(args.filterset)
    use_urls = bool(args.urls)
    use_etl = bool(args.etl)
    use_command = bool(args.command) and use_etl
    if args.command and not use_etl:
        print("Warning: --command requires --etl; skipping the management command.", file=sys.stderr)
    use_celery = bool(args.celery) and use_etl
    if args.celery and not use_etl:
        print("Warning: --celery requires --etl; skipping the Celery task.", file=sys.stderr)
    use_api_client = bool(args.api_client)
    app_title = args.app.replace('_', ' ').replace('-', ' ').title()

    sql_name = args.sql_name or snake(name)
    etl_fn = args.etl_function or f'process_{snake(name)}_query'
    cmd_name = args.command_name or snake(args.app)
    frontend_dir = Path(args.frontend_dir) if args.frontend_dir else root / 'frontend' / 'src' / 'Data' / kebab(args.app)
    typings_file = Path(args.typings_file) if args.typings_file else root / 'frontend' / 'typings' / f'{kebab(args.app)}.d.ts'

    # serializer is required by the viewset
    if use_viewset and not use_serializer:
        use_serializer = True
    # filterset is required by the viewset
    if use_viewset and not use_filterset:
        use_filterset = True
    # the viewset needs a permission class source
    if use_viewset and not use_scaffold_perms and not use_shared_tools:
        use_scaffold_perms = True

    results: list[tuple[str, str, str]] = []

    def do_append(rel: str, imports: list[str], body: str, check) -> None:
        path = app_dir / rel
        action, detail = append_module(path, imports, body, check)
        results.append((rel, action, detail))

    do_append('models.py', model_imports(name, base, fields, use_djangondor, use_manager),
              build_model_body(name, base, fields, use_djangondor, use_manager),
              lambda c: class_exists(c, name))

    if use_manager:
        do_append('managers.py', build_manager_imports(), build_manager_body(name),
                  lambda c: class_exists(c, f'{name}Manager'))

    if use_admin:
        do_append('admin.py', build_admin_imports(name), build_admin_body(name, fields),
                  lambda c: admin_registered(c, name))

    if use_serializer:
        do_append('api/serializers.py', build_serializer_imports(name), build_serializer_body(name),
                  lambda c: class_exists(c, f'{name}Serializer'))

    if use_filterset:
        do_append('api/filters.py', build_filterset_imports(name), build_filterset_body(name, fields),
                  lambda c: class_exists(c, f'{name}Filter'))

    if use_scaffold_perms:
        perm_path = app_dir / 'permissions.py'
        perm_content = perm_path.read_text() if perm_path.exists() else ''
        if class_exists(perm_content, f'{name}Access') or f'PERM_{snake(name).upper()}' in perm_content:
            results.append(('permissions.py', 'skipped', f'{perm_path} already contains the scaffold'))
        else:
            lines = ensure_imports(perm_path, build_permission_imports())
            lines = trim_trailing_blank(lines)
            body = build_permission_body(name, '\n'.join(lines))
            lines += ['', '', body]
            write_file(perm_path, '\n'.join(lines).rstrip() + '\n')
            results.append(('permissions.py', 'added', str(perm_path)))

    if use_viewset:
        do_append('api/views.py', build_view_imports(name, use_scaffold_perms, use_shared_tools, use_extend_schema),
                  build_view_body(name, app_title, use_scaffold_perms, use_shared_tools, use_extend_schema),
                  lambda c: class_exists(c, f'{name}ViewSet'))

    if use_urls and use_viewset:
        path = app_dir / 'api/urls.py'
        action, detail = append_url_register(path, name)
        results.append(('api/urls.py', action, detail))

    def do_write_once(rel: str, content: str) -> None:
        path = app_dir / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists():
            results.append((rel, 'skipped', f'{path} already exists'))
            return
        write_file(path, content)
        results.append((rel, 'added', str(path)))

    if use_etl:
        do_write_once('data_etl/__init__.py', '')
        do_write_once('data_etl/queries/__init__.py', '')
        do_write_once(f'data_etl/queries/{sql_name}.sql',
                      build_sql_body(sql_name, name, args.app, etl_fn))
        do_append(f'data_etl/{snake(name)}_etl.py', [], build_etl_body(name, sql_name, etl_fn, args.etl_lib),
                  lambda c: f'def {etl_fn}' in c)

    if use_command:
        do_write_once(f'management/__init__.py', '')
        do_write_once(f'management/commands/__init__.py', '')
        do_write_once(f'management/commands/{cmd_name}.py',
                      build_command_body(args.app, name, sql_name, etl_fn))

    if use_celery:
        # Worker functions live in developer_console/tasks.py (default location),
        # with an ExposedTaskName entry and a configs/celery-beat.ini crontab section.
        slug = f'{snake(args.app)}_{snake(name)}_etl'
        const = f'{snake(args.app).upper()}_{snake(name).upper()}_ETL'
        dc_tasks = root / 'developer_console' / 'tasks.py'
        if not dc_tasks.exists():
            print("Warning: developer_console app not found; skipping the Celery task.", file=sys.stderr)
        else:
            results.append(('developer_console/tasks.py', *append_module(
                dc_tasks, build_dc_task_imports(args.app, name, etl_fn),
                build_dc_task_body(args.app, name, etl_fn, const, slug),
                lambda c: f'def celery_{slug}' in c)))
            results.append(ensure_exposed_task_name(root / 'developer_console' / 'values.py', const, slug))
            results.append(append_beat_schedule(root / 'configs' / 'celery-beat.ini', slug))

    if use_api_client:
        frontend_dir.mkdir(parents=True, exist_ok=True)
        api_path = frontend_dir / 'api.ts'
        if interface_exists(typings_file.read_text() if typings_file.exists() else '', name):
            results.append((f'typings/{typings_file.name}', 'skipped', f'{typings_file} already contains {name}'))
        else:
            lines = trim_trailing_blank(read_lines(typings_file))
            lines += ['', '', build_types_body(name, fields, base == 'BaseTimestampModel')]
            write_file(typings_file, '\n'.join(lines).rstrip() + '\n')
            results.append((f'typings/{typings_file.name}', 'added', str(typings_file)))
        if api_list_fn(name) in (api_path.read_text() if api_path.exists() else ''):
            results.append(('api.ts', 'skipped', f'{api_path} already contains {api_list_fn(name)}'))
        else:
            lines = ensure_imports(api_path, build_api_imports())
            lines = trim_trailing_blank(lines)
            lines += ['', '', build_api_body(name)]
            write_file(api_path, '\n'.join(lines).rstrip() + '\n')
            results.append(('api.ts', 'added', str(api_path)))

    print('')
    print(f'Scaffolded {name} in app "{args.app}"')
    print('')
    for rel, action, detail in results:
        print(f'  [{action:>7}]  {rel}')
    print('')
    print('Next steps:')
    print(f'  - wire the API into the project URLConf, e.g. path("api/v1/{args.app}/", include("{args.app}.api.urls"))')
    print(f'  - run: python manage.py makemigrations {args.app}')
    if use_command:
        print(f'  - run the ETL: python manage.py {cmd_name} [--sql-name {sql_name}]')
    if use_celery:
        print(f'  - Celery worker registered in developer_console/tasks.py (ExposedTaskName entry + configs/celery-beat.ini beat section)')
    if use_api_client:
        print(f'  - frontend client written to {frontend_dir}')
        print(f'  - model typings written to {typings_file}')
    print('  - review the generated files and adjust field options as needed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
