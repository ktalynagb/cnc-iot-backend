import { render, screen } from "@testing-library/react";
import { describe, it, expect } from "vitest";
import { Thermometer } from "lucide-react";
import { KpiCard } from "../app/components/KpiCard";

describe("KpiCard", () => {
  it("renders label, value and unit", () => {
    render(
      <KpiCard label="Temperatura" value="28.5" unit="°C" Icon={Thermometer} />
    );

    expect(screen.getByText("Temperatura")).toBeInTheDocument();
    expect(screen.getByText("28.5")).toBeInTheDocument();
    expect(screen.getByText("°C")).toBeInTheDocument();
  });

  it("applies alert styles when alert prop is true", () => {
    const { container } = render(
      <KpiCard
        label="Temperatura"
        value="60.0"
        unit="°C"
        Icon={Thermometer}
        alert={true}
      />
    );

    const card = container.firstChild as HTMLElement;
    expect(card.className).toContain("bg-red-50");
  });

  it("applies normal styles when alert prop is false or omitted", () => {
    const { container } = render(
      <KpiCard label="Temperatura" value="28.5" unit="°C" Icon={Thermometer} />
    );

    const card = container.firstChild as HTMLElement;
    expect(card.className).toContain("bg-white");
  });
});
