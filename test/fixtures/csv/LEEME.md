# CSV de prueba

Todos los nombres son inventados. Aquí **nunca** van listas reales.

| Archivo | Qué simula | Resultado esperado del importador |
| --- | --- | --- |
| `01_utf8_bom_excel.csv` | Excel → "CSV UTF-8" (con BOM `EF BB BF`) | 8 alumnos, acentos correctos |
| `02_windows1252_excel.csv` | Excel → "CSV" normal en Windows (Windows-1252) | 8 alumnos, acentos correctos |
| `03_punto_y_coma.csv` | Separado por `;` | 8 alumnos |
| `04_con_encabezado.csv` | Primera fila `No.,Nombre completo` | Encabezado descartado, 8 alumnos |
| `05_numero_repetido.csv` | El N.L 3 aparece dos veces | Error en la vista previa, botón "Subir" deshabilitado |
| `06_nombre_con_coma.csv` | `3,"García Ruiz, Luis Fernando"` | 8 alumnos; el alumno 3 conserva la coma en su nombre |

Todos usan fin de línea `CRLF`, como los guarda Excel.
