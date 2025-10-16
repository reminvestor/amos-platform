#!/usr/bin/env python3
"""
Docling Document Processor Bridge
Handles advanced document parsing using IBM's Docling library
Supports both simple and semantic chunking strategies
"""

import sys
import json
import logging
import os
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
    # For semantic chunking
    from docling.chunking import HybridChunker
    from transformers import AutoTokenizer
    SEMANTIC_CHUNKING_AVAILABLE = True
except ImportError as e:
    if "chunking" in str(e) or "transformers" in str(e):
        # Docling installed but semantic chunking not available
        SEMANTIC_CHUNKING_AVAILABLE = False
        logger.warning(f"Semantic chunking not available: {e}")
    else:
        # Docling not installed at all
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

        # Initialize tokenizer for semantic chunking
        self.tokenizer = None
        if SEMANTIC_CHUNKING_AVAILABLE:
            try:
                self.tokenizer = AutoTokenizer.from_pretrained("bert-base-uncased")
                logger.info("✅ Semantic chunking available (HybridChunker)")
            except Exception as e:
                logger.warning(f"⚠️ Could not load tokenizer: {e}")

    def process_file(
        self,
        file_path: str,
        chunk_size: int = 2000,
        preserve_tables: bool = True,
        extract_images: bool = False,
        chunking_strategy: str = "simple",
        chunk_overlap: int = 200
    ) -> Dict[str, Any]:
        """
        Process a document file and extract structured chunks

        Args:
            file_path: Path to document file
            chunk_size: Maximum tokens (semantic) or characters (simple) per chunk
            preserve_tables: Keep table structure in markdown format
            extract_images: Extract image metadata
            chunking_strategy: 'simple' (paragraph-based) or 'semantic' (token-aware)
            chunk_overlap: Characters of overlap between chunks (semantic only)

        Returns:
            Dict with success status, chunks, and metadata
        """
        try:
            logger.info(f"Processing document: {file_path} (strategy: {chunking_strategy})")

            # Convert document
            result = self.converter.convert(file_path)
            doc = result.document

            chunks = []
            metadata = {
                "total_pages": 0,
                "tables_found": 0,
                "images_found": 0,
                "document_type": None,
                "chunking_strategy": chunking_strategy
            }

            # Extract metadata
            if hasattr(doc, 'pages'):
                metadata["total_pages"] = len(doc.pages)

            # Choose chunking strategy
            if chunking_strategy == "semantic" and self.tokenizer:
                chunks = self._extract_chunks_semantic(
                    doc,
                    file_path,
                    chunk_size,
                    chunk_overlap,
                    preserve_tables,
                    extract_images,
                    metadata
                )
            else:
                if chunking_strategy == "semantic":
                    logger.warning("⚠️ Semantic chunking requested but not available, falling back to simple")
                # Use simple chunking (current implementation)
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

    def _extract_chunks_semantic(
        self,
        doc,
        source: str,
        max_tokens: int,
        overlap_chars: int,
        preserve_tables: bool,
        extract_images: bool,
        metadata: Dict[str, Any]
    ) -> List[Dict[str, Any]]:
        """
        Extract chunks using semantic chunking (Ottomator-style)
        - Token-aware (not character-based)
        - Respects document structure
        - Includes overlap for context preservation
        """
        logger.info(f"🎯 Using semantic chunking (max_tokens={max_tokens}, overlap={overlap_chars})")

        try:
            # Use Docling HybridChunker
            chunker = HybridChunker(
                tokenizer=self.tokenizer,
                max_tokens=max_tokens,
                merge_peers=True,  # Merge small adjacent chunks
                heading_as_metadata=True,  # Preserve heading hierarchy
                respect_section_boundaries=True
            )

            # Chunk the document
            doc_chunks = chunker.chunk(doc)

            enriched_chunks = []
            for i, chunk in enumerate(doc_chunks):
                # Extract heading hierarchy
                headings = []
                if hasattr(chunk, 'meta') and hasattr(chunk.meta, 'headings'):
                    headings = chunk.meta.headings

                # Extract page number
                page_num = 1
                if hasattr(chunk, 'meta') and hasattr(chunk.meta, 'page'):
                    page_num = chunk.meta.page

                # Build chunk content
                content = chunk.text

                # Add overlap from previous chunk
                if i > 0 and overlap_chars > 0:
                    prev_text = doc_chunks[i-1].text[-overlap_chars:]
                    content = prev_text + "\n\n" + content

                # Check for tables and images
                has_table = hasattr(chunk, 'meta') and getattr(chunk.meta, 'has_tables', False)
                has_image = hasattr(chunk, 'meta') and getattr(chunk.meta, 'has_images', False)

                chunk_data = {
                    "content": content,
                    "metadata": {
                        "source": source,
                        "type": "semantic_chunk",
                        "page": page_num,
                        "heading_hierarchy": headings,
                        "chunk_index": i,
                        "total_chunks": len(doc_chunks),
                        "has_table": has_table,
                        "has_image": has_image,
                        "has_overlap": i > 0 and overlap_chars > 0,
                        "token_count": len(self.tokenizer.encode(content)) if self.tokenizer else None
                    }
                }

                enriched_chunks.append(chunk_data)

            logger.info(f"✅ Semantic chunking produced {len(enriched_chunks)} chunks")
            return enriched_chunks

        except Exception as e:
            logger.error(f"❌ Semantic chunking failed: {e}, falling back to simple")
            # Fall back to simple chunking
            return self._extract_chunks(
                doc, source, max_tokens * 4,  # Approximate tokens→chars
                preserve_tables, extract_images, metadata
            )

    def _extract_chunks(
        self,
        doc,
        source: str,
        chunk_size: int,
        preserve_tables: bool,
        extract_images: bool,
        metadata: Dict[str, Any]
    ) -> List[Dict[str, Any]]:
        """Extract structured chunks from document (simple paragraph-based)"""
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
            "error": "Usage: python docling_processor.py <file_path> [chunk_size] [preserve_tables] [extract_images] [chunking_strategy] [chunk_overlap]",
            "chunks": []
        }))
        sys.exit(1)

    file_path = sys.argv[1]
    chunk_size = int(sys.argv[2]) if len(sys.argv) > 2 else 2000
    preserve_tables = sys.argv[3].lower() == 'true' if len(sys.argv) > 3 else True
    extract_images = sys.argv[4].lower() == 'true' if len(sys.argv) > 4 else False
    chunking_strategy = sys.argv[5] if len(sys.argv) > 5 else os.getenv('RAG_CHUNKING_STRATEGY', 'simple')
    chunk_overlap = int(sys.argv[6]) if len(sys.argv) > 6 else int(os.getenv('RAG_CHUNK_OVERLAP', '200'))

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
        extract_images=extract_images,
        chunking_strategy=chunking_strategy,
        chunk_overlap=chunk_overlap
    )

    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
