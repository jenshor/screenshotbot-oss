
setupLiveOnAttach(".acceptance-left-side-bar", function () {
    $(".review-list a", $(this)).click(function (e) {

        var href = $(this).attr("href");

        $.ajax({
            url: href,
            error: function () {
                swAlert("Something went wrong, please refresh the page and try again");
            },
            success: function(data){
                var html = $(data);
                $(".review-panel").html(html);
                callLiveOnAttach($(".review-panel"));
            }
        });

        e.preventDefault();
    });
});


setupLiveOnAttach(".review-input", function () {
    var reviewInput = $(this);
    function replace(href) {
        $.ajax({
            url: href,
            error: function () {
                swAlert("Something went wrong, please refresh the page and try again");
            },
            success: function(data) {
                var html = $(data);
                reviewInput.replaceWith(html);
                callLiveOnAttach(html);
            }
        });
    };

    function refreshLeftSideBar() {
        var panel = $(".acceptance-left-side-bar");
        var href = panel.data("refresh");
        $.ajax({
            url: href,
            error: function () {
                swAlert("Something went wrong, please refresh the page and try again");
            },
            success: function (data) {
                var html = $(data);
                panel.replaceWith(html);
                callLiveOnAttach(html);
            }
        });
    }

    function updateTab(klass) {
        var id = reviewInput.closest(".tab-pane").attr("id");
        var title = $("[data-bs-target='#" + id + "'] > span");

        title.removeClass("text-success")
            .removeClass("text-danger");

        title.addClass(klass);
        refreshLeftSideBar();
    }
    $(".accept-link", $(this)).click(function (e) {
        replace($(this).attr("href"));
        updateTab("text-success");
        e.preventDefault();
    });

    $(".reject-link", $(this)).click(function (e) {
        replace($(this).attr("href"));
        updateTab("text-danger");
        e.preventDefault();
    });

});
