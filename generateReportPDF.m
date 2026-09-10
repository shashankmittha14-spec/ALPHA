%% ---- REPORT GENERATION FUNCTION (Lab-report style) ----
function pdfPath = generateReportPDF(mode, data, sourceFileName, outFolder)
%   mode: 'rejected' | 'uncertain' | 'graded'

    repFig = figure('Visible', 'off', 'Position', [100 100 900 1200], ...
        'Color', 'white');

    % ---- Letterhead header band ----
    annotation(repFig, 'rectangle', [0 0.94 1 0.06], ...
        'FaceColor', [0.10 0.28 0.45], 'Color', 'none');
    annotation(repFig, 'textbox', [0.04 0.945 0.7 0.05], ...
        'String', 'AI-Based Diabetic Retinopathy Screening', ...
        'FontSize', 15, 'FontWeight', 'bold', 'Color', 'white', ...
        'EdgeColor', 'none', 'VerticalAlignment', 'middle');
    annotation(repFig, 'textbox', [0.70 0.945 0.26 0.05], ...
        'String', 'SIH 2026 | PS 26038', ...
        'FontSize', 10, 'Color', [0.85 0.9 1], 'EdgeColor', 'none', ...
        'HorizontalAlignment', 'right', 'VerticalAlignment', 'middle');

    % ---- Sample / Image info block ----
    [~, baseName, ~] = fileparts(sourceFileName);
    infoLeft = { ...
        sprintf('Image ID       : %s', baseName), ...
        sprintf('Source File    : %s', sourceFileName), ...
        sprintf('Screening Date : %s', string(datetime('now','Format','dd/MM/yyyy'))) };
    infoRight = { ...
        sprintf('Time           : %s', string(datetime('now','Format','hh:mm:ss a'))), ...
        sprintf('Pipeline Stage : %s', pickStage(mode)), ...
        sprintf('Report Status  : %s', 'Final') };

    annotation(repFig, 'textbox', [0.04 0.865 0.5 0.07], ...
        'String', strjoin(infoLeft, newline), 'FontSize', 9.5, ...
        'FontName', 'Courier New', 'EdgeColor', 'none', 'VerticalAlignment', 'top');
    annotation(repFig, 'textbox', [0.55 0.865 0.42 0.07], ...
        'String', strjoin(infoRight, newline), 'FontSize', 9.5, ...
        'FontName', 'Courier New', 'EdgeColor', 'none', 'VerticalAlignment', 'top');

    annotation(repFig, 'line', [0.04 0.96], [0.86 0.86], 'Color', [0.7 0.7 0.7]);

    yCursor = 0.835;

    switch mode
        case 'rejected'
            yCursor = drawStatusBanner(repFig, yCursor, 'IMAGE REJECTED -- NOT PROCESSED', ...
                [0.7 0 0], [1 0.9 0.9]);
            yCursor = drawBodyText(repFig, yCursor, ['Reason: ', data.reason]);

            axOrig = axes(repFig, 'Position', [0.32 yCursor-0.26 0.36 0.24]);
            imshow(data.origImg, 'Parent', axOrig);
            title(axOrig, 'Uploaded Image', 'FontSize', 10);
            yCursor = yCursor - 0.28;

            yCursor = drawSectionTitle(repFig, yCursor, 'Test Report');
            if ~isempty(data.stage1)
                s = data.stage1;
                rows = { ...
                    'Focus Score',        sprintf('%.3f', s.focusScore),  '>= 0.35'; ...
                    'Illumination Score', sprintf('%.3f', s.illumScore),  '>= 0.35'; ...
                    'Field-of-View Score',sprintf('%.3f', s.fovScore),    '>= 0.50'; ...
                    'Overall Score',      sprintf('%.3f', s.overallScore),'--'; ...
                    'Gradable',           string(s.gradable),             '--' };
            else
                rows = { 'Retina-color check score', sprintf('%.3f', data.colorScore), '>= 0.20' };
            end
            yCursor = drawResultsTable(repFig, yCursor, {'Metric','Result','Reference'}, [0.42 0.22 0.26], rows);
            yCursor = drawScoreExplanation(repFig, yCursor);

        case 'uncertain'
            yCursor = drawStatusBanner(repFig, yCursor, ...
                sprintf('PREDICTION UNCERTAIN (confidence %.0f%%)', data.confidence*100), ...
                [0.7 0.5 0], [1 0.95 0.8]);
            yCursor = drawBodyText(repFig, yCursor, ...
                'Recommendation: manual review by a qualified professional required.');

            axOrig = axes(repFig, 'Position', [0.32 yCursor-0.26 0.36 0.24]);
            imshow(data.origImg, 'Parent', axOrig);
            title(axOrig, 'Uploaded Image', 'FontSize', 10);
            yCursor = yCursor - 0.28;

            yCursor = drawSectionTitle(repFig, yCursor, 'Test Report');
            s = data.stage1;
            rows = { ...
                'Focus Score',        sprintf('%.3f', s.focusScore),  '>= 0.35'; ...
                'Illumination Score', sprintf('%.3f', s.illumScore),  '>= 0.35'; ...
                'Field-of-View Score',sprintf('%.3f', s.fovScore),    '>= 0.50'; ...
                'Overall Score',      sprintf('%.3f', s.overallScore),'--'; ...
                'Model Confidence',   sprintf('%.0f%%', data.confidence*100), '>= 50%' };
            yCursor = drawResultsTable(repFig, yCursor, {'Metric','Result','Reference'}, [0.42 0.22 0.26], rows);
            yCursor = drawScoreExplanation(repFig, yCursor);

        case 'graded'
            switch data.predictedGrade
                case {0, 1}
                    urgency = 'Routine follow-up (annual screening)'; uCol = [0 0.5 0];
                case 2
                    urgency = 'Refer to ophthalmologist within a few weeks'; uCol = [0.85 0.55 0];
                case {3, 4}
                    urgency = 'URGENT referral to ophthalmologist required'; uCol = [0.8 0 0];
                otherwise
                    urgency = 'Unknown'; uCol = [0 0 0];
            end

            yCursor = drawStatusBanner(repFig, yCursor, ...
                sprintf('Grade %d (%s)  |  Confidence %.0f%%', ...
                data.predictedGrade, data.gradeText, data.confidence*100), ...
                [0.15 0.15 0.15], [0.94 0.94 0.94]);
            yCursor = drawBodyText(repFig, yCursor, ['Referral Urgency: ', urgency], uCol);

            imgH = 0.20;
            imgTop = yCursor;              % top of the image row
            imgBottom = imgTop - imgH;     % bottom of the image row (fixed anchor)

            axOrig = axes(repFig, 'Position', [0.05 imgBottom 0.27 imgH]);
            imshow(data.origImg, 'Parent', axOrig);
            title(axOrig, 'Original', 'FontSize', 9);

            axCam = axes(repFig, 'Position', [0.365 imgBottom 0.27 imgH]);
            imshow(data.origImg, 'Parent', axCam); hold(axCam, 'on');
            imagesc(axCam, data.gradCAMMap, 'AlphaData', 0.5);
            colormap(axCam, 'jet'); hold(axCam, 'off');
            title(axCam, 'Grad-CAM (Explainable AI)', 'FontSize', 9);

            axSeg = axes(repFig, 'Position', [0.68 imgBottom 0.27 imgH]);
            if ~isempty(data.segRGB)
                imshow(data.segRGB, 'Parent', axSeg);
            else
                text(0.5, 0.5, 'Unavailable', 'Parent', axSeg, 'HorizontalAlignment', 'center');
                axis(axSeg, 'off');
            end
            title(axSeg, 'Segmentation', 'FontSize', 9);

            % ---- Segmentation legend: anchored to imgBottom, full width, 2 rows x 4 cols ----
            legendItems = { ...
                [0   0.4 1  ], 'Vessel'; ...
                [1   1   0  ], 'Microaneurysm'; ...
                [0   0.8 0  ], 'Optic Disc'; ...
                [0.9 0   0  ], 'Hemorrhage'; ...
                [0   0.9 0.9], 'Fovea'; ...
                [1   0.55 0 ], 'Exudate'; ...
                [0.9 0   0.9], 'Neovascularization' };

            legendTitleGap = 0.018;   % gap between images and "Segmentation Legend:" label
            legendTitleH   = 0.016;
            legendRowH     = 0.018;
            legendCols     = 4;      % 4 items per row -> 2 rows for 7 items
            legendColW     = 0.92 / legendCols;
            legendLeft     = 0.04;

            legendTitleY = imgBottom - legendTitleGap - legendTitleH;
            annotation(repFig, 'textbox', [legendLeft legendTitleY 0.4 legendTitleH], ...
                'String', 'Segmentation Legend:', 'FontSize', 8, 'FontWeight', 'bold', ...
                'EdgeColor', 'none');

            nItems = size(legendItems, 1);
            nLegendRows = ceil(nItems / legendCols);
            legendGridTop = legendTitleY - 0.004;

            for i = 1:nItems
                colIdx = mod(i-1, legendCols);          % 0..legendCols-1, left to right
                rowIdx = floor((i-1) / legendCols);      % 0..nLegendRows-1, top to bottom
                xBase = legendLeft + colIdx * legendColW;
                yBox  = legendGridTop - rowIdx * legendRowH;

                annotation(repFig, 'rectangle', [xBase, yBox, 0.012, 0.012], ...
                    'FaceColor', legendItems{i,1}, 'Color', 'none');
                annotation(repFig, 'textbox', [xBase + 0.016, yBox - 0.004, legendColW - 0.02, legendRowH], ...
                    'String', legendItems{i,2}, 'FontSize', 7.5, 'EdgeColor', 'none', ...
                    'VerticalAlignment', 'middle');
            end

            legendBottom = legendGridTop - nLegendRows * legendRowH;

            % ---- Test Report section: anchored to legendBottom, fixed gap ----
            sectionGap = 0.02;
            yCursor = legendBottom - sectionGap;
            yCursor = drawSectionTitle(repFig, yCursor, 'Test Report');
            s = data.stage1;
            rows = { ...
                'Focus Score',        sprintf('%.3f', s.focusScore),  '>= 0.35'; ...
                'Illumination Score', sprintf('%.3f', s.illumScore),  '>= 0.35'; ...
                'Field-of-View Score',sprintf('%.3f', s.fovScore),    '>= 0.50'; ...
                'Overall Quality',    sprintf('%.3f', s.overallScore),'--'; ...
                'Predicted DR Grade', sprintf('%d (%s)', data.predictedGrade, data.gradeText), '0-4'; ...
                'Model Confidence',   sprintf('%.0f%%', data.confidence*100), '>= 50%' };
            yCursor = drawResultsTable(repFig, yCursor, {'Metric','Result','Reference'}, [0.42 0.22 0.26], rows);
            yCursor = drawScoreExplanation(repFig, yCursor);
    end

    % ---- Footer disclaimer ----
    annotation(repFig, 'line', [0.04 0.96], [0.045 0.045], 'Color', [0.8 0.8 0.8]);
    annotation(repFig, 'textbox', [0.04 0.005 0.92 0.04], ...
        'String', ['This report is generated by an AI-assisted screening tool and is ', ...
        'intended to support, not replace, clinical judgement. All flagged cases ', ...
        'should be reviewed by a qualified professional.'], ...
        'FontSize', 7.5, 'EdgeColor', 'none', 'Color', [0.45 0.45 0.45], ...
        'HorizontalAlignment', 'center');

    [~, baseName, ~] = fileparts(sourceFileName);
    timestamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
    pdfName = sprintf('DR_Report_%s_%s_%s.pdf', mode, baseName, timestamp);
    pdfPath = fullfile(outFolder, pdfName);

    exportgraphics(repFig, pdfPath, 'ContentType', 'vector');
    close(repFig);
end

%% ---- Helper: explanation of the three quality scores ----
function yNext = drawScoreExplanation(fig, yTop)
    h = 0.02;
    annotation(fig, 'textbox', [0.04 yTop-h 0.92 h], ...
        'String', 'What These Scores Mean', 'FontSize', 10, 'FontWeight', 'bold', ...
        'EdgeColor', 'none');
    yTop = yTop - h - 0.004;

    explainText = [ ...
        "Focus Score (0-1): sharpness of the image, measured via edge/detail strength inside the retina circle. Low scores indicate blur that can hide fine lesions." newline ...
        "Illumination Score (0-1): exposure and contrast quality, measured on the green channel (best vessel/lesion contrast). Low scores indicate under/over-exposed or low-contrast capture." newline ...
        "Field-of-View Score (0-1): how much of the expected retinal field is actually captured. Low scores indicate cropping, misalignment, or eyelid obstruction." newline ...
        "An image must clear all three minimum thresholds to be marked Gradable and proceed to DR classification." ];

    boxH = 0.075;
    annotation(fig, 'textbox', [0.04 yTop-boxH 0.92 boxH], ...
        'String', explainText, 'FontSize', 7.5, 'EdgeColor', [0.8 0.8 0.8], ...
        'BackgroundColor', [0.97 0.97 0.97], 'VerticalAlignment', 'top', ...
        'HorizontalAlignment', 'left');
    yNext = yTop - boxH - 0.01;
end