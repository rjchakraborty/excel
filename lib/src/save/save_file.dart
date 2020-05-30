part of excel;

class Save {
  Excel _excel;
  Map<String, ArchiveFile> _archiveFiles;
  List<CellStyle> _innerCellStyle;
  Save._(Excel excel) {
    this._excel = excel;
    this._archiveFiles = Map<String, ArchiveFile>();
    _innerCellStyle = List<CellStyle>();
  }

  Future<List> _save() async {
    if (_excel._colorChanges) {
      _processStylesFile();
    }
    _setSheetElements();
    _setSharedStrings();

    if (_excel._mergeChanges) {
      _setMerge();
    }

    for (var xmlFile in _excel._xmlFiles.keys) {
      var xml = _excel._xmlFiles[xmlFile].toString();
      var content = utf8.encode(xml);
      _archiveFiles[xmlFile] = ArchiveFile(xmlFile, content.length, content);
    }
    return ZipEncoder().encode(_cloneArchive(_excel._archive));
  }

  Archive _cloneArchive(Archive archive) {
    var clone = Archive();
    archive.files.forEach((file) {
      if (file.isFile) {
        ArchiveFile copy;
        if (_archiveFiles.containsKey(file.name)) {
          copy = _archiveFiles[file.name];
        } else {
          var content = (file.content as Uint8List).toList();
          var compress = !_noCompression.contains(file.name);
          copy = ArchiveFile(file.name, content.length, content)
            ..compress = compress;
        }
        clone.addFile(copy);
      }
    });
    return clone;
  }

  /// Writing cell contained text into the excel sheet files.
  _setSheetElements() {
    _excel._sharedStrings = List<String>();
    _excel._sheetMap.forEach((sheet, value) {
      // clear the previous contents of the sheet if it exists in order to reduce the time to find and compare with the sheet rows
      // and hence just do the work of putting the data only i.e. creating new rows
      if (_excel._sheets[sheet] != null &&
          _excel._sheets[sheet].children.isNotEmpty) {
        _excel._sheets[sheet].children.clear();
      }
      /** Above function is important in order to wipe out the old contents of the sheet. */

      value._sheetData.forEach((rowIndex, map) {
        map.forEach((columnIndex, data) {
          if (data.value != null) {
            var foundRow = _findRowByIndex(_excel._sheets[sheet], rowIndex);
            _updateCell(sheet, foundRow, columnIndex, rowIndex, data.value);
          }
        });
      });
    });
  }

  /// Writing the merged cells information into the excel properties files.
  _setMerge() {
    _selfCorrectSpanMap(_excel);
    _excel._mergeChangeLook.forEach((s) {
      if (_isContain(_excel._sheetMap['$s']) &&
          _excel._sheetMap['$s']._spanList != null &&
          _excel._sheetMap['$s']._spanList.isNotEmpty &&
          _excel._xmlSheetId.containsKey(s) &&
          _excel._xmlFiles.containsKey(_excel._xmlSheetId[s])) {
        Iterable<XmlElement> iterMergeElement = _excel
            ._xmlFiles[_excel._xmlSheetId[s]]
            .findAllElements('mergeCells');
        XmlElement mergeElement;
        if (iterMergeElement.isNotEmpty) {
          mergeElement = iterMergeElement.first;
        } else {
          if (_excel._xmlFiles[_excel._xmlSheetId[s]]
                  .findAllElements('worksheet')
                  .length >
              0) {
            int index = _excel._xmlFiles[_excel._xmlSheetId[s]]
                .findAllElements('worksheet')
                .first
                .children
                .indexOf(_excel._xmlFiles[_excel._xmlSheetId[s]]
                    .findAllElements("sheetData")
                    .first);
            if (index == -1) {
              _damagedExcel();
            }
            _excel._xmlFiles[_excel._xmlSheetId[s]]
                .findAllElements('worksheet')
                .first
                .children
                .insert(
                    index + 1,
                    XmlElement(XmlName('mergeCells'),
                        [XmlAttribute(XmlName('count'), '0')]));

            mergeElement = _excel._xmlFiles[_excel._xmlSheetId[s]]
                .findAllElements('mergeCells')
                .first;
          } else {
            _damagedExcel();
          }
        }

        List<String> _spannedItems =
            List<String>.from(_excel._sheetMap['$s'].spannedItems);

        [
          ['count', _spannedItems.length.toString()],
        ].forEach((value) {
          if (mergeElement.getAttributeNode(value[0]) == null) {
            mergeElement.attributes
                .add(XmlAttribute(XmlName(value[0]), value[1]));
          } else {
            mergeElement.getAttributeNode(value[0]).value = value[1];
          }
        });

        mergeElement.children.clear();

        _spannedItems.forEach((value) {
          mergeElement.children.add(XmlElement(XmlName('mergeCell'),
              [XmlAttribute(XmlName('ref'), '$value')], []));
        });
      }
    });
  }

  /// Writing Font Color in [xl/styles.xml] from the Cells of the sheets.

  _processStylesFile() {
    _innerCellStyle = List<CellStyle>();
    List<String> innerPatternFill = List<String>(),
        innerFontColor = List<String>();

    _excel._sheetMap.forEach((sheetName, sheetObject) {
      sheetObject._sheetData.forEach((_, colMap) {
        colMap.forEach((_, dataObject) {
          if (dataObject != null) {
            int pos = _checkPosition(_innerCellStyle, dataObject.cellStyle);
            if (pos == -1) {
              _innerCellStyle.add(dataObject.cellStyle);
            }
          }
        });
      });
    });

    _innerCellStyle.forEach((cellStyle) {
      String fontColor = cellStyle.getFontColorHex,
          backgroundColor = cellStyle.getBackgroundColorHex;

      if (!_excel._fontColorHex.contains(fontColor) &&
          !innerFontColor.contains(fontColor)) {
        innerFontColor.add(fontColor);
      }
      if (!_excel._patternFill.contains(backgroundColor) &&
          !innerPatternFill.contains(backgroundColor)) {
        innerPatternFill.add(backgroundColor);
      }
    });

    XmlElement fonts =
        _excel._xmlFiles['xl/styles.xml'].findAllElements('fonts').first;

    var fontAttribute = fonts.getAttributeNode('count');
    if (fontAttribute != null) {
      fontAttribute.value =
          '${_excel._fontColorHex.length + innerFontColor.length}';
    } else {
      fonts.attributes.add(XmlAttribute(XmlName('count'),
          '${_excel._fontColorHex.length + innerFontColor.length}'));
    }

    innerFontColor.forEach((colorValue) =>
        fonts.children.add(XmlElement(XmlName('font'), [], [
          XmlElement(
              XmlName('color'), [XmlAttribute(XmlName('rgb'), colorValue)], [])
        ])));

    XmlElement fills =
        _excel._xmlFiles['xl/styles.xml'].findAllElements('fills').first;

    var fillAttribute = fills.getAttributeNode('count');

    if (fillAttribute != null) {
      fillAttribute.value =
          '${_excel._patternFill.length + innerPatternFill.length}';
    } else {
      fills.attributes.add(XmlAttribute(XmlName('count'),
          '${_excel._patternFill.length + innerPatternFill.length}'));
    }

    innerPatternFill.forEach((color) {
      if (color.length >= 2) {
        if (color.substring(0, 2).toUpperCase() == 'FF') {
          fills.children.add(XmlElement(XmlName('fill'), [], [
            XmlElement(XmlName('patternFill'), [
              XmlAttribute(XmlName('patternType'), 'solid')
            ], [
              XmlElement(XmlName('fgColor'),
                  [XmlAttribute(XmlName('rgb'), color)], []),
              XmlElement(
                  XmlName('bgColor'), [XmlAttribute(XmlName('rgb'), color)], [])
            ])
          ]));
        } else if (color == "none" ||
            color == "gray125" ||
            color == "lightGray") {
          fills.children.add(XmlElement(XmlName('fill'), [], [
            XmlElement(XmlName('patternFill'),
                [XmlAttribute(XmlName('patternType'), color)], [])
          ]));
        }
      } else {
        _damagedExcel(text: "Corrupted Styles Found");
      }
    });

    XmlElement celx =
        _excel._xmlFiles['xl/styles.xml'].findAllElements('cellXfs').first;
    var cellAttribute = celx.getAttributeNode('count');

    if (cellAttribute != null) {
      cellAttribute.value =
          '${_excel._cellStyleList.length + _innerCellStyle.length}';
    } else {
      celx.attributes.add(XmlAttribute(XmlName('count'),
          '${_excel._cellStyleList.length + _innerCellStyle.length}'));
    }

    _innerCellStyle.forEach((cellStyle) {
      String backgroundColor = cellStyle.getBackgroundColorHex,
          fontColor = cellStyle.getFontColorHex;

      HorizontalAlign horizontalALign = cellStyle.getHorizontalAlignment;
      VerticalAlign verticalAlign = cellStyle.getVericalAlignment;
      TextWrapping textWrapping = cellStyle.getTextWrapping;
      int backgroundIndex = innerPatternFill.indexOf(backgroundColor),
          fontIndex = innerFontColor.indexOf(fontColor);

      var attributes = <XmlAttribute>[
        XmlAttribute(XmlName('borderId'), '0'),
        XmlAttribute(XmlName('fillId'),
            '${backgroundIndex == -1 ? 0 : backgroundIndex + _excel._patternFill.length}'),
        XmlAttribute(XmlName('fontId'),
            '${fontIndex == -1 ? 0 : fontIndex + _excel._fontColorHex.length}'),
        XmlAttribute(XmlName('numFmtId'), '0'),
        XmlAttribute(XmlName('xfId'), '0'),
      ];

      if ((_excel._patternFill.contains(backgroundColor) ||
              innerPatternFill.contains(backgroundColor)) &&
          backgroundColor != "none" &&
          backgroundColor != "gray125" &&
          backgroundColor.toLowerCase() != "lightgray") {
        attributes.add(XmlAttribute(XmlName('applyFill'), '1'));
      }

      if ((_excel._fontColorHex.contains(fontColor) ||
          innerFontColor.contains(fontColor))) {
        attributes.add(XmlAttribute(XmlName('applyFont'), '1'));
      }

      var children = <XmlElement>[];

      if (horizontalALign != HorizontalAlign.Left ||
          textWrapping != null ||
          verticalAlign != VerticalAlign.Bottom) {
        attributes.add(XmlAttribute(XmlName('applyAlignment'), '1'));
        var childAttributes = <XmlAttribute>[];

        if (textWrapping != null) {
          childAttributes.add(XmlAttribute(
              XmlName(textWrapping == TextWrapping.Clip
                  ? 'shrinkToFit'
                  : 'wrapText'),
              '1'));
        }

        if (verticalAlign != VerticalAlign.Bottom) {
          String ver = verticalAlign == VerticalAlign.Top ? 'top' : 'center';
          childAttributes.add(XmlAttribute(XmlName('vertical'), '$ver'));
        }

        if (horizontalALign != HorizontalAlign.Left) {
          String hor =
              horizontalALign == HorizontalAlign.Right ? 'right' : 'center';
          childAttributes.add(XmlAttribute(XmlName('horizontal'), '$hor'));
        }

        children.add(XmlElement(XmlName('alignment'), childAttributes, []));
      }

      celx.children.add(XmlElement(XmlName('xf'), attributes, children));
    });
  }

  /// Writing the value of excel cells into the separate
  /// sharedStrings file so as to minimize the size of excel files.
  _setSharedStrings() {
    String count = _excel._sharedStrings.length.toString();
    List uniqueList = _excel._sharedStrings.toSet().toList();
    String uniqueCount = uniqueList.length.toString();

    XmlElement shareString = _excel
        ._xmlFiles['xl/${_excel._sharedStringsTarget}']
        .findAllElements('sst')
        .first;

    [
      ['count', count],
      ['uniqueCount', uniqueCount]
    ].forEach((value) {
      if (shareString.getAttributeNode(value[0]) == null) {
        shareString.attributes.add(XmlAttribute(XmlName(value[0]), value[1]));
      } else {
        shareString.getAttributeNode(value[0]).value = value[1];
      }
    });

    shareString.children.clear();

    _excel._sharedStrings.forEach((string) {
      shareString.children.add(XmlElement(XmlName('si'), [], [
        XmlElement(XmlName('t'), [], [XmlText(string)])
      ]));
    });
  }

  ///
  XmlElement _findRowByIndex(XmlElement table, int rowIndex) {
    XmlElement row;
    var rows = _findRows(table);

    var currentIndex = 0;
    for (var currentRow in rows) {
      currentIndex = _getRowNumber(currentRow) - 1;
      if (currentIndex >= rowIndex) {
        row = currentRow;
        break;
      }
    }

    // Create row if required
    if (row == null || currentIndex != rowIndex) {
      row = __insertRow(table, row, rowIndex);
    }

    return row;
  }

  XmlElement _createRow(int rowIndex) => XmlElement(XmlName('row'),
      [XmlAttribute(XmlName('r'), (rowIndex + 1).toString())], []);

  XmlElement __insertRow(XmlElement table, XmlElement lastRow, int rowIndex) {
    var row = _createRow(rowIndex);
    if (lastRow == null) {
      table.children.add(row);
    } else {
      var index = table.children.indexOf(lastRow);
      table.children.insert(index, row);
    }
    return row;
  }

  XmlElement _insertCell(String sheet, XmlElement row, XmlElement lastCell,
      int columnIndex, int rowIndex, dynamic value) {
    var cell = _createCell(sheet, columnIndex, rowIndex, value);
    if (lastCell == null) {
      row.children.add(cell);
    } else {
      var index = row.children.indexOf(lastCell);
      row.children.insert(index, cell);
    }
    return cell;
  }

  XmlElement _replaceCell(String sheet, XmlElement row, XmlElement lastCell,
      int columnIndex, int rowIndex, dynamic value) {
    var index = lastCell == null ? 0 : row.children.indexOf(lastCell);
    var cell = _createCell(sheet, columnIndex, rowIndex, value);
    row.children
      ..removeAt(index)
      ..insert(index, cell);
    return cell;
  }

  // Manage value's type
  XmlElement _createCell(
      String sheet, int columnIndex, int rowIndex, dynamic value) {
    if (!_excel._sharedStrings.contains(value.toString())) {
      _excel._sharedStrings.add(value.toString());
    }

    String rC = getCellId(columnIndex, rowIndex);

    var attributes = <XmlAttribute>[
      XmlAttribute(XmlName('r'), rC),
      XmlAttribute(XmlName('t'), 's'),
    ];

    if (_excel._colorChanges &&
        _isContain(_excel._sheetMap[sheet]) &&
        _isContain(_excel._sheetMap[sheet]._sheetData) &&
        _isContain(_excel._sheetMap[sheet]._sheetData[rowIndex]) &&
        _isContain(_excel._sheetMap[sheet]._sheetData[rowIndex][columnIndex]) &&
        _excel._sheetMap[sheet]._sheetData[rowIndex][columnIndex].cellStyle !=
            null) {
      CellStyle cellStyle =
          _excel._sheetMap[sheet]._sheetData[rowIndex][columnIndex].cellStyle;
      int upperLevelPos = _checkPosition(_excel._cellStyleList, cellStyle);
      if (upperLevelPos == -1) {
        int lowerLevelPos = _checkPosition(_innerCellStyle, cellStyle);
        if (lowerLevelPos != -1) {
          upperLevelPos = lowerLevelPos + _excel._cellStyleList.length;
        } else {
          upperLevelPos = 0;
        }
      }
      attributes.insert(
        1,
        XmlAttribute(XmlName('s'), '$upperLevelPos'),
      );
    } else if (_excel._colorChanges &&
        _excel._cellStyleReferenced.containsKey(sheet) &&
        _excel._cellStyleReferenced[sheet].containsKey(rC)) {
      attributes.insert(
        1,
        XmlAttribute(XmlName('s'), '${_excel._cellStyleReferenced[sheet][rC]}'),
      );
    }
    var children = value == null
        ? <XmlElement>[]
        : <XmlElement>[
            XmlElement(XmlName('v'), [], [
              XmlText(
                  _excel._sharedStrings.indexOf(value.toString()).toString())
            ]),
          ];
    return XmlElement(XmlName('c'), attributes, children);
  }

  XmlElement _updateCell(String sheet, XmlElement node, int columnIndex,
      int rowIndex, dynamic value) {
    XmlElement cell;
    var cells = _findCells(node);

    var currentIndex = 0; // cells could be empty
    for (var currentCell in cells) {
      currentIndex = _getCellNumber(currentCell);
      if (currentIndex >= columnIndex) {
        cell = currentCell;
        break;
      }
    }

    if (cell == null || currentIndex != columnIndex) {
      cell = _insertCell(sheet, node, cell, columnIndex, rowIndex, value);
    } else {
      cell = _replaceCell(sheet, node, cell, columnIndex, rowIndex, value);
    }

    return cell;
  }
}
