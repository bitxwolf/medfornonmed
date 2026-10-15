import Foundation

public struct MedicalLiteratureItem: Identifiable {
    public let id: String
    public let title: String
    public let source: String // e.g., "StatPearls", "PubMed"
    public let excerpt: String
    public let fmaIds: [String]
    public let url: String
}

public struct AnatomicalEdge {
    public let sourceId: String
    public let targetId: String
    public let relation: String
    public let clinicalNote: String
}

public final class MedicalKnowledgeGraph {
    public static let shared = MedicalKnowledgeGraph()

    public let literatureChunks: [MedicalLiteratureItem] = [
        MedicalLiteratureItem(
            id: "NBK459269",
            title: "Acute Myocardial Infarction and Coronary Atherosclerosis",
            source: "StatPearls [Internet]",
            excerpt: "Acute myocardial infarction (AMI) results from sudden occlusion of a coronary artery, predominantly the left anterior descending (LAD) artery, by a ruptured atherosclerotic plaque and superimposed thrombus. Cessation of blood flow leads to severe cellular hypoxia, lactic acidosis, and within 20 to 40 minutes, irreversible cardiomyocyte necrosis progressing from the subendocardium to the epicardium.",
            fmaIds: ["FMA_7101", "FMA_7097", "FMA_7088"],
            url: "https://www.ncbi.nlm.nih.gov/books/NBK459269/"
        ),
        MedicalLiteratureItem(
            id: "NBK537158",
            title: "Physiology, Cardiac Cycle and Blood Flow",
            source: "StatPearls [Internet]",
            excerpt: "Deoxygenated blood returns from systemic circulation via the vena cava into the right atrium, passes across the tricuspid valve into the right ventricle, and is ejected into the pulmonary artery toward alveolar capillaries where gas exchange occurs. Oxygenated blood returns through pulmonary veins into the left atrium, passes through the mitral valve to the high-pressure left ventricle, and is pumped into the aorta.",
            fmaIds: ["FMA_7096", "FMA_7098", "FMA_7099", "FMA_7097", "FMA_3734"],
            url: "https://www.ncbi.nlm.nih.gov/books/NBK537158/"
        ),
        MedicalLiteratureItem(
            id: "PMID_31484124",
            title: "Microvascular Obstruction and Hemodynamics in Ischemic Heart Disease",
            source: "PubMed Clinical Reviews",
            excerpt: "Intracoronary thrombosis triggers downstream microvascular embolization and no-reflow phenomenon. Erythrocyte aggregation and stagnation within ischemic microvessels exacerbate local metabolic deficit, producing diagnostic cyanotic tissue discoloration and regional wall motion abnormalities visible on echocardiography.",
            fmaIds: ["FMA_7101", "FMA_7097"],
            url: "https://pubmed.ncbi.nlm.nih.gov/31484124/"
        )
    ]

    public let graphEdges: [AnatomicalEdge] = [
        AnatomicalEdge(
            sourceId: "FMA_7101",
            targetId: "FMA_7097",
            relation: "ARTERIAL_SUPPLY",
            clinicalNote: "LAD supplies the anterior two-thirds of the interventricular septum and left ventricular apex."
        ),
        AnatomicalEdge(
            sourceId: "FMA_7096",
            targetId: "FMA_7098",
            relation: "FLOWS_INTO",
            clinicalNote: "Right atrium fills right ventricle via tricuspid orifice during ventricular diastole."
        ),
        AnatomicalEdge(
            sourceId: "FMA_7098",
            targetId: "FMA_7310",
            relation: "FLOWS_INTO",
            clinicalNote: "Right ventricle ejects deoxygenated blood through pulmonary valve into pulmonary circulation."
        ),
        AnatomicalEdge(
            sourceId: "FMA_7099",
            targetId: "FMA_7097",
            relation: "FLOWS_INTO",
            clinicalNote: "Left atrium fills left ventricle through mitral valve."
        ),
        AnatomicalEdge(
            sourceId: "FMA_7097",
            targetId: "FMA_3734",
            relation: "FLOWS_INTO",
            clinicalNote: "Left ventricle pumps stroke volume against systemic afterload into the aorta."
        ),
        AnatomicalEdge(
            sourceId: "FMA_7480",
            targetId: "FMA_7088",
            relation: "OCCLUDES_VIEW_OF",
            clinicalNote: "Thoracic ribcage and sternum physically shield and visually occlude the anterior heart."
        )
    ]

    public func findRelevantLiterature(for query: String) -> [MedicalLiteratureItem] {
        let q = query.lowercased()
        return literatureChunks.filter { item in
            item.title.lowercased().contains(q) ||
            item.excerpt.lowercased().contains(q) ||
            item.fmaIds.contains { q.contains($0.lowercased()) }
        }
    }
}
