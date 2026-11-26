# =============================================================================
# Clip_Peaks: individual Action Unit peaks across clips
#
# Interactive exploration of AU peaks associated with changes in felt intensity,
# by emotional condition and AU. Data: peaks.rds (created by
# scripts/prepare_clip_peaks_app.R; participants are pseudonymized).
# =============================================================================

library(shiny)
library(dplyr)
library(ggplot2)
library(patchwork)

peaks <- readRDS("peaks.rds")

conditions <- sort(unique(peaks$Condition))
aus        <- sort(unique(peaks$AU))

feature_label <- function(var) {
  if (var == "height") "Peak height" else "Peak duration (s)"
}

ui <- fluidPage(
  titlePanel("Individual Action Unit peaks across clips"),
  sidebarLayout(
    sidebarPanel(
      width = 3,
      selectInput("cond", "Emotional condition", conditions, selected = "Amusement"),
      selectInput("au", "Action Unit", aus, selected = "AU12"),
      sliderInput("bin", "Histogram bin width (s)", min = 1, max = 10, value = 2, step = 1),
      radioButtons("var", "Peak feature",
                   c("Peak height" = "height", "Peak duration (s)" = "dur_s")),
      hr(),
      helpText("Each point is one AU peak associated with a change in felt intensity,",
               "for one participant (rows, sorted by number of peaks), plotted at its",
               "maximum. Clips are shown side by side, with panel width proportional",
               "to clip duration. The histogram shows the number of peaks in each time",
               "bin, indicating moments of synchrony across viewers. The selected",
               "feature is mapped to point size and colour, and shown in the",
               "by-clip view.")
    ),
    mainPanel(
      width = 9,
      tabsetPanel(
        tabPanel("Timeline", plotOutput("timeline", height = "700px")),
        tabPanel("By clip",  plotOutput("byclip",   height = "500px")),
        tabPanel("Summary",  tableOutput("summary"))
      )
    )
  )
)

server <- function(input, output, session) {

  selected <- reactive({
    peaks %>% filter(Condition == input$cond, AU == input$au)
  })

  output$timeline <- renderPlot({
    d <- selected()
    validate(need(nrow(d) > 0, "No peaks for this combination."))
    ord <- d %>% count(Participant) %>% arrange(n) %>% pull(Participant)
    d$Participant <- factor(d$Participant, levels = ord)
    lab <- feature_label(input$var)

    top <- ggplot(d, aes(x = time_s)) +
      geom_histogram(binwidth = input$bin, boundary = 0, fill = "firebrick", alpha = 0.6) +
      facet_grid(~ Clip, scales = "free_x", space = "free_x") +
      labs(x = NULL, y = "Peaks", title = paste0(input$au, ", ", tolower(input$cond))) +
      theme_minimal(base_size = 13) +
      theme(axis.text.x      = element_blank(),
            panel.grid.minor = element_blank(),
            strip.text       = element_text(face = "bold", size = 9),
            panel.spacing    = unit(0.8, "lines"))

    bottom <- ggplot(d, aes(x = time_s, y = Participant)) +
      geom_point(aes(size = .data[[input$var]], colour = .data[[input$var]]), alpha = 0.7) +
      facet_grid(~ Clip, scales = "free_x", space = "free_x") +
      scale_colour_gradient(low = "grey75", high = "firebrick") +
      scale_size_continuous(range = c(0.5, 3.5)) +
      guides(colour = guide_legend(), size = guide_legend()) +
      labs(x = "Time within clip (s)", y = "Participants", colour = lab, size = lab) +
      theme_minimal(base_size = 13) +
      theme(axis.text.y      = element_blank(),
            panel.grid.minor = element_blank(),
            strip.text       = element_blank(),
            panel.spacing    = unit(0.8, "lines"))

    top / bottom + plot_layout(heights = c(1, 4))
  })

  output$byclip <- renderPlot({
    d <- selected()
    validate(need(nrow(d) > 0, "No peaks for this combination."))
    ggplot(d, aes(x = Clip, y = .data[[input$var]])) +
      geom_violin(fill = "grey90", colour = NA) +
      geom_boxplot(width = 0.15, outlier.shape = NA) +
      labs(x = NULL, y = feature_label(input$var),
           title = paste0(input$au, ", ", tolower(input$cond), ": peaks by clip")) +
      theme_minimal(base_size = 13) +
      theme(axis.text.x = element_text(angle = 30, hjust = 1))
  })

  output$summary <- renderTable({
    selected() %>%
      group_by(Clip) %>%
      summarise(`Peaks`               = n(),
                `Participants`        = n_distinct(Participant),
                `Median height`       = median(height),
                `Median duration (s)` = median(dur_s),
                .groups = "drop")
  }, digits = 2)
}

shinyApp(ui, server)
