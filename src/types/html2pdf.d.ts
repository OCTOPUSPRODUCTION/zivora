declare module "html2pdf.js" {
  type Html2PdfWorker = {
    set(options: Record<string, unknown>): Html2PdfWorker;
    from(element: HTMLElement): Html2PdfWorker;
    toPdf(): Html2PdfWorker;
    get(
      key: string
    ): Promise<{
      internal: {
        getNumberOfPages(): number;
        pageSize: {
          getWidth(): number;
          getHeight(): number;
        };
      };
      setPage(pageNumber: number): void;
      setFontSize(size: number): void;
      setTextColor(
        red: number,
        green: number,
        blue: number
      ): void;
      text(
        text: string,
        x: number,
        y: number,
        options?: {
          align?: "left" | "center" | "right";
        }
      ): void;
    }>;
    save(): Promise<void>;
  };

  type Html2PdfFactory = () => Html2PdfWorker;

  const html2pdf: Html2PdfFactory;

  export default html2pdf;
}
