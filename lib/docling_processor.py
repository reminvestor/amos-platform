#!/usr/bin/env python3
"""
Docling Document Processor Bridge
Handles advanced document parsing using IBM's Docling library
"""

import sys
import json
import logging
from pathlib import Path
from typing import Dict, List, Any, Optional

try:
    from docling.document_converter import DocumentConverter, PdfFormatOption
    from docling.datamodel.base_models import InputFormat
    from docling.datamodel.pipeline_options import (
        PdfPipelineOptions,
        TableFormerMode,
        EasyOcrOptions
    )
    from docling_core.types.doc import (
        ImageRefMode,
        PictureItem,
        TableItem,
        DocItemLabel
    )
except ImportError as e:
    print(json.dumps({
        "success": False,
        "error": f"Docling not installed: {e}",
        "chunks": []
    }))
    sys.exit(1)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class DoclingProcessor:
    """Process documents using Docling for enhanced extraction"""

    def __init__(self):
        """Initialize Docling converter with optimized settings"""
        # Configure pipeline for best quality
        pipeline_options = PdfPipelineOptions()
        pipeline_options.do_ocr = True
        pipeline_options.do_table_structure = True
        pipeline_options.table_structure_options.mode = TableFormerMode.ACCURATE

        # Configure PDF format options
        format_options = {
            InputFormat.PDF: PdfFormatOption(
                pipeline_options=pipeline_options
            )
        }

        self.converter = DocumentConverter(
            format_options=format_options
        )

    def process_file(
        self,
        file_path: str,
        chunk_size: int = 2000,
        preserve_tables: bool = True,
        extract_images: bool = False
    ) -> Dict[str, Any]:
        """
        Process a document file and extract structured chunks

        Args:
            file_path: Path to document file
            chunk_size: Maximum characters per chunk
            preserve_tables: Keep table structure in markdown format
            extract_images: Extract image metadata

        Returns:
            Dict with success status, chunks, and metadata
        """
        try:
            logger.info(f"Processing document: {file_path}")

            # Convert document
            result = self.converter.convert(file_path)
            doc = result.document

            chunks = []
            metadata = {
                "total_pages": 0,
                "tables_found": 0,
                "images_found": 0,
                "document_type": None
            }

            # Extract metadata
            if hasattr(doc, 'pages'):
                metadata["total_pages"] = len(doc.pages)

            # Process document structure
            chunks = self._extract_chunks(
                doc,
                file_path,
                chunk_size,
                preserve_tables,
                extract_images,
                metadata
            )

            logger.info(f"Extracted {len(chunks)} chunks from {file_path}")

            return {
                "success": True,
                "chunks": chunks,
                "metadata": metadata
            }

        except Exception as e:
            logger.error(f"Error processing {file_path}: {str(e)}")
            return {
                "success": False,
                "error": str(e),
                "chunks": []
            }

    def _extract_chunks(
        self,
        doc,
        source: str,
        chunk_size: int,
        preserve_tables: bool,
        extract_images: bool,
        metadata: Dict[str, Any]
    ) -> List[Dict[str, Any]]:
        """Extract structured chunks from document"""
        chunks = []
        current_chunk = []
        current_size = 0
        current_page = 1

        # Iterate through document items
        for item, level in doc.iterate_items():
            item_text = ""
            item_metadata = {
                "source": source,
                "type": "text",
                "page": current_page
            }

            # Handle different item types
            if item.label == DocItemLabel.PARAGRAPH:
                item_text = self._get_text(item)
                item_metadata["type"] = "paragraph"

            elif item.label == DocItemLabel.TITLE:
                item_text = f"## {self._get_text(item)}"
                item_metadata["type"] = "heading"

            elif item.label == DocItemLabel.SECTION_HEADER:
                item_text = f"### {self._get_text(item)}"
                item_metadata["type"] = "section_header"

            elif item.label == DocItemLabel.LIST_ITEM:
                item_text = f"- {self._get_text(item)}"
                item_metadata["type"] = "list_item"

            elif item.label == DocItemLabel.TABLE and preserve_tables:
                item_text = self._format_table(item)
                item_metadata["type"] = "table"
                metadata["tables_found"] += 1

            elif item.label == DocItemLabel.PICTURE and extract_images:
                item_metadata.update(self._extract_image_info(item))
                item_metadata["type"] = "image"
                metadata["images_found"] += 1
                # Don't add text for images, just metadata
                chunks.append({
                    "content": f"[Image: {item_metadata.get('caption', 'No caption')}]",
                    "metadata": item_metadata
                })
                continue

            elif item.label == DocItemLabel.CODE:
                item_text = f"```\n{self._get_text(item)}\n```"
                item_metadata["type"] = "code"

            else:
                item_text = self._get_text(item)

            # Update page number if available
            if hasattr(item, 'prov') and item.prov:
                for prov in item.prov:
                    if hasattr(prov, 'page_no'):
                        current_page = prov.page_no
                        break

            # Chunk management
            if item_text:
                text_length = len(item_text)

                # If single item exceeds chunk size, split it
                if text_length > chunk_size:
                    # Save current chunk if exists
                    if current_chunk:
                        chunks.append({
                            "content": "\n\n".join(current_chunk),
                            "metadata": item_metadata
                        })
                        current_chunk = []
                        current_size = 0

                    # Split large text
                    for i in range(0, len(item_text), chunk_size):
                        chunk_text = item_text[i:i+chunk_size]
                        chunks.append({
                            "content": chunk_text,
                            "metadata": {**item_metadata, "chunked": True}
                        })

                # Check if adding this item would exceed chunk size
                elif current_size + text_length > chunk_size and current_chunk:
                    # Save current chunk
                    chunks.append({
                        "content": "\n\n".join(current_chunk),
                        "metadata": item_metadata
                    })
                    current_chunk = [item_text]
                    current_size = text_length

                else:
                    # Add to current chunk
                    current_chunk.append(item_text)
                    current_size += text_length

        # Add remaining chunk
        if current_chunk:
            chunks.append({
                "content": "\n\n".join(current_chunk),
                "metadata": {
                    "source": source,
                    "type": "text",
                    "page": current_page
                }
            })

        return chunks

    def _get_text(self, item) -> str:
        """Extract text from document item"""
        if hasattr(item, 'text'):
            return item.text.strip() if item.text else ""
        return ""

    def _format_table(self, table_item) -> str:
        """Format table as markdown"""
        if not hasattr(table_item, 'data') or not table_item.data:
            return "[Empty Table]"

        try:
            # Get table data
            table_data = table_item.data

            if hasattr(table_data, 'to_dataframe'):
                # Convert to markdown using pandas
                df = table_data.to_dataframe()
                return df.to_markdown(index=False)

            elif hasattr(table_data, 'grid'):
                # Format grid as markdown
                grid = table_data.grid
                if not grid or not grid[0]:
                    return "[Empty Table]"

                # Create markdown table
                lines = []

                # Header
                lines.append("| " + " | ".join(str(cell) for cell in grid[0]) + " |")
                lines.append("| " + " | ".join("---" for _ in grid[0]) + " |")

                # Rows
                for row in grid[1:]:
                    lines.append("| " + " | ".join(str(cell) for cell in row) + " |")

                return "\n".join(lines)

        except Exception as e:
            logger.warning(f"Error formatting table: {e}")

        return "[Table - formatting error]"

    def _extract_image_info(self, image_item) -> Dict[str, Any]:
        """Extract image metadata"""
        info = {}

        if hasattr(image_item, 'caption'):
            info["caption"] = image_item.caption

        if hasattr(image_item, 'prov') and image_item.prov:
            for prov in image_item.prov:
                if hasattr(prov, 'bbox'):
                    info["bbox"] = {
                        "x": prov.bbox.l,
                        "y": prov.bbox.t,
                        "width": prov.bbox.r - prov.bbox.l,
                        "height": prov.bbox.b - prov.bbox.t
                    }
                    break

        return info


def main():
    """CLI entry point"""
    if len(sys.argv) < 2:
        print(json.dumps({
            "success": False,
            "error": "Usage: python docling_processor.py <file_path> [chunk_size] [preserve_tables] [extract_images]",
            "chunks": []
        }))
        sys.exit(1)

    file_path = sys.argv[1]
    chunk_size = int(sys.argv[2]) if len(sys.argv) > 2 else 2000
    preserve_tables = sys.argv[3].lower() == 'true' if len(sys.argv) > 3 else True
    extract_images = sys.argv[4].lower() == 'true' if len(sys.argv) > 4 else False

    if not Path(file_path).exists():
        print(json.dumps({
            "success": False,
            "error": f"File not found: {file_path}",
            "chunks": []
        }))
        sys.exit(1)

    processor = DoclingProcessor()
    result = processor.process_file(
        file_path,
        chunk_size=chunk_size,
        preserve_tables=preserve_tables,
        extract_images=extract_images
    )

    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
